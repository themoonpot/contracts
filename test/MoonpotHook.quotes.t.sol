// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import "../contracts/MoonpotHook.sol";
import "../contracts/MoonpotToken.sol";
import "../contracts/mocks/MockUSDC.sol";
import "./mocks/MockPermit2.sol";

/// @notice Exposes MoonpotHook's pure internal pricing math for unit testing
/// without spinning up a real Uniswap v4 pool. The high-level `quoteSell` and
/// `quoteBuy` view paths (which read `extsload` from the live PoolManager) are
/// exercised by the Tier 2 fixture-based tests.
contract TestableHook is MoonpotHook {
    constructor(
        IPoolManager _poolManager,
        address _posm,
        address _permit2,
        address _usdc,
        address _tmp,
        address _owner
    ) MoonpotHook(_poolManager, _posm, _permit2, _usdc, _tmp, _owner) {}

    function exposed_calculateTax(int24 ticksAboveFloor) external view returns (uint24) {
        return _calculateTax(ticksAboveFloor);
    }

    function exposed_computeMaxTmpSell(bool usdcIsCurrency0, uint160 sqrtPriceX96)
        external
        view
        returns (uint256)
    {
        return _computeMaxTmpSell(usdcIsCurrency0, sqrtPriceX96);
    }
}

contract MoonpotHookQuotesTest is Test {
    uint160 constant HOOK_FLAGS =
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
    int24 constant TICK_SPACING = 60;

    TestableHook hook;
    MoonpotToken tmp;
    MockUSDC usdc;
    MockPermit2 permit2;

    address owner = address(this);

    function setUp() public {
        permit2 = new MockPermit2();
        tmp = new MoonpotToken();
        usdc = new MockUSDC();
        hook = _deployHook(IPoolManager(address(this)));
        _initializePoolKey();
    }

    function _deployHook(IPoolManager _pm) internal returns (TestableHook) {
        bytes memory creationCode = type(TestableHook).creationCode;
        bytes memory args = abi.encode(_pm, address(permit2), address(permit2), address(usdc), address(tmp), owner);
        (address addr, bytes32 salt) = HookMiner.find(address(this), HOOK_FLAGS, creationCode, args);
        TestableHook h = new TestableHook{salt: salt}(
            _pm,
            address(permit2),
            address(permit2),
            address(usdc),
            address(tmp),
            owner
        );
        require(address(h) == addr, "addr mismatch");
        return h;
    }

    function _initializePoolKey() internal {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdc) < address(tmp) ? address(usdc) : address(tmp)),
            currency1: Currency.wrap(address(usdc) < address(tmp) ? address(tmp) : address(usdc)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        hook.beforeInitialize(address(this), key, 0);
    }

    /* --------------------------------- _calculateTax --------------------------------- */
    // Defaults: baseDefenseTax = 3_000, maxDefenseTax = 500_000, taxRampTicks = 4_080.

    function testTaxAtFloor() public view {
        // ticksAboveFloor == 0 → maxDefenseTax
        assertEq(hook.exposed_calculateTax(0), 500_000);
    }

    function testTaxBelowFloor() public view {
        // negative ticks (price below floor) → maxDefenseTax
        assertEq(hook.exposed_calculateTax(-1), 500_000);
        assertEq(hook.exposed_calculateTax(-10_000), 500_000);
    }

    function testTaxAboveRamp() public view {
        // ticksAboveFloor >= taxRampTicks → baseDefenseTax
        assertEq(hook.exposed_calculateTax(4_080), 3_000);
        assertEq(hook.exposed_calculateTax(10_000), 3_000);
    }

    function testTaxAtRampMidpoint() public view {
        // At ramp midpoint (2_040 ticks), tax ≈ (max + base) / 2.
        // Exact: max - reduction = max - (max-base)*midpoint/rampTicks
        //      = 500_000 - 497_000*2040/4080 = 500_000 - 248_500 = 251_500
        assertEq(hook.exposed_calculateTax(2_040), 251_500);
    }

    function testTaxIsMonotonicallyDecreasing() public view {
        // Linear ramp: each step up reduces tax. Check 10 evenly-spaced points.
        uint24 prev = type(uint24).max;
        int24 step = hook.taxRampTicks() / 10;
        for (int24 t = 0; t <= hook.taxRampTicks(); t += step) {
            uint24 tax = hook.exposed_calculateTax(t);
            assertLe(tax, prev, "tax should not increase as we move above the floor");
            prev = tax;
        }
    }

    function testTaxReactsToParamUpdate() public {
        hook.setDefenseParams(1_000, 100_000, 1_000);
        assertEq(hook.exposed_calculateTax(0), 100_000);
        assertEq(hook.exposed_calculateTax(1_000), 1_000);
        // midpoint of new ramp
        assertEq(hook.exposed_calculateTax(500), 50_500);
    }

    /* --------------------------------- _computeMaxTmpSell ----------------------------- */

    function testMaxSellZeroLiquidityReturnsZero() public {
        // protocolLiquidity defaults to 0 → maxTmpSell = 0 regardless of price
        assertEq(hook.exposed_computeMaxTmpSell(true, TickMath.getSqrtPriceAtTick(0)), 0);
        assertEq(hook.exposed_computeMaxTmpSell(false, TickMath.getSqrtPriceAtTick(0)), 0);
    }

    function testMaxSellWhenUsdcIsCurrency0_priceAtOrAboveFloorUpperReturnsZero() public {
        hook.setManager(address(this));
        // Establish floor at tick 1500 → floorTickUpper = 1560.
        // When usdc is currency0, sqrtPriceX96 >= sqrt(floorTickUpper) means price ≤ floor (USDC≤TMP).
        // i.e. price is already at/above the floor "from below" → no more room → maxSell = 0.
        hook.setCurrentFloorTick(1_500);
        hook.setPositionId(1, 1_440, 1_560, 1_000_000);

        uint160 sqrtAtUpper = TickMath.getSqrtPriceAtTick(1_560);
        assertEq(hook.exposed_computeMaxTmpSell(true, sqrtAtUpper), 0);
        assertEq(hook.exposed_computeMaxTmpSell(true, sqrtAtUpper + 1), 0);
    }

    function testMaxSellWhenUsdcIsCurrency0_priceBelowFloorUpperIsPositive() public {
        hook.setManager(address(this));
        hook.setCurrentFloorTick(1_500);
        hook.setPositionId(1, 1_440, 1_560, 1_000_000);

        uint160 sqrtBelowFloor = TickMath.getSqrtPriceAtTick(1_000);
        uint256 maxSell = hook.exposed_computeMaxTmpSell(true, sqrtBelowFloor);
        assertGt(maxSell, 0);
    }

    function testMaxSellWhenTmpIsCurrency0_priceAtOrBelowFloorLowerReturnsZero() public {
        hook.setManager(address(this));
        hook.setCurrentFloorTick(-1_500);
        hook.setPositionId(1, -1_560, -1_440, 1_000_000);

        uint160 sqrtAtLower = TickMath.getSqrtPriceAtTick(-1_560);
        assertEq(hook.exposed_computeMaxTmpSell(false, sqrtAtLower), 0);
        assertEq(hook.exposed_computeMaxTmpSell(false, sqrtAtLower - 1), 0);
    }

    function testMaxSellWhenTmpIsCurrency0_priceAboveFloorLowerIsPositive() public {
        hook.setManager(address(this));
        hook.setCurrentFloorTick(-1_500);
        hook.setPositionId(1, -1_560, -1_440, 1_000_000);

        uint160 sqrtAbove = TickMath.getSqrtPriceAtTick(-1_000);
        uint256 maxSell = hook.exposed_computeMaxTmpSell(false, sqrtAbove);
        assertGt(maxSell, 0);
    }

    function testMaxSellScalesWithLiquidity() public {
        hook.setManager(address(this));
        hook.setCurrentFloorTick(1_500);
        hook.setPositionId(1, 1_440, 1_560, 1_000_000);
        uint160 sqrtBelowFloor = TickMath.getSqrtPriceAtTick(1_000);
        uint256 small = hook.exposed_computeMaxTmpSell(true, sqrtBelowFloor);

        // setPositionId is one-shot in spirit but the contract allows re-set
        // (id == 0 is a no-op; id != 0 overwrites). Re-set with 10× liquidity.
        hook.setPositionId(1, 1_440, 1_560, 10_000_000);
        uint256 big = hook.exposed_computeMaxTmpSell(true, sqrtBelowFloor);

        // Linear-ish in liquidity (FullMath path)
        assertApproxEqRel(big, small * 10, 0.001e18); // within 0.1%
    }
}
