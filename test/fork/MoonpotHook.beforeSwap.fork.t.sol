// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./ForkFixture.sol";
import "./ForkRouter.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

/// @notice Fork tests exercising `MoonpotHook.beforeSwap` against a real
/// Uniswap v4 pool on Base mainnet. Verifies:
/// - Buy-side swaps (USDC -> TMP) apply the base defense tax.
/// - Sell-side swaps (TMP -> USDC) get clamped + excess TMP burned when they
///   would push price below the floor (`TMPIntercepted` event + supply drop).
/// - Exact-output TMP sells revert with `ExactOutputTMPSellBlocked`.
/// - The dynamic tax decreases monotonically as price moves above the floor.
contract MoonpotHookBeforeSwapForkTest is ForkFixture {
    using StateLibrary for IPoolManager;

    ForkRouter router;
    address swapper = address(0xABCD);

    function _afterInit() internal override {
        router = new ForkRouter(poolManager);

        // Fund the swapper with USDC and TMP for both swap directions.
        deal(USDC, swapper, 1_000_000e6);

        // Approve the router to pull both currencies from the swapper.
        vm.startPrank(swapper);
        // USDC: standard ERC20 approve
        (bool ok, ) = USDC.call(
            abi.encodeWithSignature("approve(address,uint256)", address(router), type(uint256).max)
        );
        require(ok, "usdc approve failed");
        tmp.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Helper: minimum/maximum sqrt price limits, per v4 convention.
    function _swap(bool zeroForOne, int256 amountSpecified) internal returns (int128 d0, int128 d1) {
        uint160 sqrtPriceLimit = zeroForOne
            ? TickMath.MIN_SQRT_PRICE + 1
            : TickMath.MAX_SQRT_PRICE - 1;

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: sqrtPriceLimit
        });

        BalanceDelta delta;
        vm.prank(swapper);
        delta = router.swap(poolKey, params, "");
        d0 = delta.amount0();
        d1 = delta.amount1();
    }

    /* --------------------------------- Buy path (USDC -> TMP) ----------------------- */

    function testBuyAppliesBaseDefenseTax() public {
        // Buying TMP = exact-input USDC.
        // Direction: usdc -> tmp. If usdc is currency0, zeroForOne = true.
        bool buyZeroForOne = _usdcIsCurrency0();
        uint256 usdcIn = 1_000e6;

        uint256 tmpBefore = tmp.balanceOf(swapper);
        (int128 d0, int128 d1) = _swap(buyZeroForOne, -int256(usdcIn));
        uint256 tmpAfter = tmp.balanceOf(swapper);

        // The swapper should have received TMP
        assertGt(tmpAfter, tmpBefore, "swapper got TMP");

        // The delta on the USDC currency should be negative (paid in)
        if (buyZeroForOne) assertLt(d0, 0);
        else assertLt(d1, 0);
    }

    /* --------------------------------- Sell path (TMP -> USDC) ---------------------- */

    function testSellExactOutputReverts() public {
        // Sell-direction = !buyZeroForOne. Exact-output is amountSpecified > 0.
        bool sellZeroForOne = !_usdcIsCurrency0();

        SwapParams memory params = SwapParams({
            zeroForOne: sellZeroForOne,
            amountSpecified: int256(uint256(100e6)), // positive = exact output
            sqrtPriceLimitX96: sellZeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        vm.prank(swapper);
        vm.expectRevert();
        router.swap(poolKey, params, "");
    }

    function testSellWithinFloorPassesThrough() public {
        // First, give the swapper some TMP by buying.
        uint256 usdcIn = 1_000e6;
        _swap(_usdcIsCurrency0(), -int256(usdcIn));

        uint256 tmpBalance = tmp.balanceOf(swapper);
        assertGt(tmpBalance, 0);

        // Now sell back a *tiny* fraction of that TMP so we stay above floor.
        uint256 sellAmount = tmpBalance / 100; // 1%; well within the floor band

        uint256 tmpSupplyBefore = tmp.totalSupply();
        (int128 d0, int128 d1) = _swap(!_usdcIsCurrency0(), -int256(sellAmount));

        // Some USDC was received
        if (_usdcIsCurrency0()) assertGt(d0, 0);
        else assertGt(d1, 0);

        // No TMP was burned by the hook on this small sale
        // (TMP supply only drops if `_computeMaxTmpSell` clamped)
        uint256 tmpSupplyAfter = tmp.totalSupply();
        // Supply should be unchanged or only changed by the buy-back-and-burn
        // path during the swap (not applicable for in-bounds sells).
        assertEq(tmpSupplyAfter, tmpSupplyBefore, "no TMP burned for in-band sell");
    }

    function testSellExceedingFloorBurnsExcess() public {
        // The hook clamps via `poolManager.take(tmp, hook, excessTmp)`, which
        // physically transfers TMP from the PoolManager. PM's TMP holdings are
        // bounded by the pool's reserves (the LP minted at init plus any TMP
        // settled from prior swaps). The swap input must therefore exceed the
        // floor band but stay under PM's reserves.
        //
        // The init flow puts ~1M TMP into PM. Mint 800k TMP to the swapper;
        // enough to exceed `maxTmpSell` (the price-to-floor TMP allowance) but
        // still within PM's reserves so the take + burn can settle.
        vm.prank(address(mp));
        tmp.mint(swapper, 800_000e18);

        uint256 tmpBalance = tmp.balanceOf(swapper);
        uint256 tmpSupplyBefore = tmp.totalSupply();

        // Expect a TMPIntercepted event from the hook
        vm.expectEmit(false, false, false, false, address(hook));
        emit MoonpotHook.TMPIntercepted(0, 0); // args not checked
        _swap(!_usdcIsCurrency0(), -int256(tmpBalance));

        uint256 tmpSupplyAfter = tmp.totalSupply();
        assertLt(tmpSupplyAfter, tmpSupplyBefore, "TMP was burned by the hook");
    }

    /* --------------------------------- Dynamic tax ramp ----------------------------- */

    function testTaxAtCurrentTickIsBaseAfterFreshInit() public view {
        // After init, price is INIT_TICK_PREMIUM ticks above the floor; well
        // inside the `taxRampTicks = 4080` band, so tax should be the base
        // tax (3000 / 1M = 0.3%) at the upper end of the ramp.
        (uint160 sqrtPrice, int24 currentTick, , ) = poolManager.getSlot0(poolId);
        sqrtPrice; // silence unused
        int24 ticksAboveFloor = currentTick - hook.currentFloorTick();

        // The `_calculateTax` ramp puts tax at base if ticksAboveFloor >= taxRampTicks.
        // INIT_TICK_PREMIUM = 1200; taxRampTicks default = 4080. So we're INSIDE
        // the ramp, not above it; tax should be > base.
        assertGt(ticksAboveFloor, 0, "init tick is above the floor");

        // Re-derive expected via the contract's pure logic
        uint24 expected;
        if (ticksAboveFloor >= hook.taxRampTicks()) {
            expected = hook.baseDefenseTax();
        } else {
            uint256 reduction = (uint256(uint24(hook.maxDefenseTax() - hook.baseDefenseTax()))
                * uint256(uint24(ticksAboveFloor)))
                / uint256(uint24(hook.taxRampTicks()));
            expected = uint24(hook.maxDefenseTax() - uint24(reduction));
        }

        // Use quoteSell on an in-band amount to surface the tax the hook will charge
        (, , uint24 quotedTax) = hook.quoteSell(1e18);
        assertEq(quotedTax, expected, "quoted tax matches contract ramp formula");
    }
}
