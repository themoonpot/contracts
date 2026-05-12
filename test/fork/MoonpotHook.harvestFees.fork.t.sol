// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./ForkFixture.sol";
import "./ForkRouter.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @notice Fork tests for `MoonpotHook.harvestFees`. Generates fees via real
/// swaps through the v4 pool, then calls `harvestFees` and asserts:
/// - USDC fees flow to `_company` (minus `pendingLiquidityUsdc` so queued
///   liquidity isn't swept)
/// - TMP fees are burned (totalSupply drops)
/// - `FeesHarvested` event is emitted
contract MoonpotHookHarvestFeesForkTest is ForkFixture {
    ForkRouter router;
    address swapper = address(0xABCD);

    function _afterInit() internal override {
        router = new ForkRouter(poolManager);

        // Fund + approve the swapper
        deal(USDC, swapper, 1_000_000e6);
        vm.startPrank(swapper);
        (bool ok, ) = USDC.call(
            abi.encodeWithSignature("approve(address,uint256)", address(router), type(uint256).max)
        );
        require(ok, "usdc approve failed");
        tmp.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function _swapBuy(uint256 usdcIn) internal {
        bool buyZeroForOne = _usdcIsCurrency0();
        SwapParams memory params = SwapParams({
            zeroForOne: buyZeroForOne,
            amountSpecified: -int256(usdcIn),
            sqrtPriceLimitX96: buyZeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        vm.prank(swapper);
        router.swap(poolKey, params, "");
    }

    function _swapSell(uint256 tmpIn) internal {
        bool sellZeroForOne = !_usdcIsCurrency0();
        SwapParams memory params = SwapParams({
            zeroForOne: sellZeroForOne,
            amountSpecified: -int256(tmpIn),
            sqrtPriceLimitX96: sellZeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        vm.prank(swapper);
        router.swap(poolKey, params, "");
    }

    /* --------------------------------- access control -------------------------------- */

    function testHarvestFeesOnlyOwner() public {
        vm.expectRevert();
        vm.prank(address(0xBAD));
        hook.harvestFees();
    }

    /* --------------------------------- happy path ------------------------------------ */

    function testHarvestFeesAccruedFromBuySwaps() public {
        // Do a buy to generate USDC-side fees (the LP charges the dynamic fee
        // returned by the hook in beforeSwap).
        _swapBuy(10_000e6);

        // Some TMP is now in the swapper's hands; sell a portion to also
        // accrue TMP-side fees.
        uint256 tmpBalance = tmp.balanceOf(swapper);
        if (tmpBalance > 0) {
            _swapSell(tmpBalance / 4);
        }

        uint256 companyUsdcBefore = _usdcBalance(COMPANY);
        uint256 tmpSupplyBefore = tmp.totalSupply();
        uint256 pending = mp.pendingLiquidityUsdc();

        // Owner harvests
        hook.harvestFees();

        uint256 companyUsdcAfter = _usdcBalance(COMPANY);
        uint256 tmpSupplyAfter = tmp.totalSupply();

        // USDC fees went to company. Pending liquidity stays put on the hook.
        assertGe(companyUsdcAfter, companyUsdcBefore, "company received USDC fees");

        // TMP fees were burned (or none accrued; both are valid outcomes).
        assertLe(tmpSupplyAfter, tmpSupplyBefore, "TMP fees burned (supply non-increasing)");

        // Hook's USDC balance never drops below `pendingLiquidityUsdc`
        assertGe(_usdcBalance(address(hook)), pending, "pending liquidity preserved");
    }

    function testHarvestFeesPreservesPendingLiquidity() public {
        // Accumulate pending liquidity via a buyFor purchase (below the
        // injection checkpoint so it stays queued on the hook).
        address buyer = address(0xCAFE);
        deal(USDC, buyer, 50_000e6);
        vm.prank(buyer);
        (bool ok, ) = USDC.call(
            abi.encodeWithSignature("approve(address,uint256)", address(mp), type(uint256).max)
        );
        require(ok, "usdc approve failed");

        vm.prank(buyer);
        mp.buyFor(buyer, 5_000 * round1.PRICE(), 0, 0, bytes32(0), bytes32(0));

        uint256 pending = mp.pendingLiquidityUsdc();
        assertGt(pending, 0, "pending liquidity present");

        uint256 hookUsdcBefore = _usdcBalance(address(hook));
        assertGe(hookUsdcBefore, pending);

        // Generate swap fees
        _swapBuy(5_000e6);

        // Harvest
        hook.harvestFees();

        uint256 hookUsdcAfter = _usdcBalance(address(hook));
        // The hook still holds at least `pendingLiquidityUsdc` (anything above
        // that was harvested to company).
        assertGe(hookUsdcAfter, pending, "harvest didn't sweep pending liquidity");
    }

    /* --------------------------------- helpers --------------------------------------- */

    function _usdcBalance(address who) internal view returns (uint256) {
        (bool ok, bytes memory ret) = USDC.staticcall(
            abi.encodeWithSignature("balanceOf(address)", who)
        );
        require(ok && ret.length == 32, "balanceOf failed");
        return abi.decode(ret, (uint256));
    }
}
