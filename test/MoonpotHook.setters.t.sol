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
import "../contracts/MoonpotHook.sol";
import "../contracts/MoonpotToken.sol";
import "../contracts/mocks/MockUSDC.sol";
import "./mocks/MockPermit2.sol";

/// @notice Pure setter / access-control tests for MoonpotHook.
/// The test contract acts as the pool manager so we can drive `beforeInitialize`
/// directly to populate the hook's `poolKey` without spinning up a real v4 pool.
contract MoonpotHookSettersTest is Test {
    uint160 constant HOOK_FLAGS =
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
    int24 constant TICK_SPACING = 60;

    MoonpotHook hook;
    MoonpotToken tmp;
    MockUSDC usdc;
    MockPermit2 permit2;

    address owner = address(this); // also acts as pool manager via ImmutableState
    address managerAddr = address(0xBEEF); // the wagmi-style "manager" the hook trusts
    address stranger = address(0xBAD);

    function setUp() public {
        permit2 = new MockPermit2();
        tmp = new MoonpotToken();
        usdc = new MockUSDC();
        hook = _deployHook(IPoolManager(address(this)));
        _initializePoolKey();
    }

    /// @dev Mines a CREATE2 salt for the required hook flag bits, then deploys.
    function _deployHook(IPoolManager _poolManager) internal returns (MoonpotHook) {
        bytes memory creationCode = type(MoonpotHook).creationCode;
        bytes memory args = abi.encode(_poolManager, address(permit2), address(permit2), address(usdc), address(tmp), owner);
        (address addr, bytes32 salt) = HookMiner.find(address(this), HOOK_FLAGS, creationCode, args);
        MoonpotHook h = new MoonpotHook{salt: salt}(
            _poolManager,
            address(permit2),
            address(permit2),
            address(usdc),
            address(tmp),
            owner
        );
        require(address(h) == addr, "deployed address mismatch");
        return h;
    }

    /// @dev Drives `beforeInitialize` as the pool manager so `poolKey` is set
    /// with our chosen tickSpacing (needed by `setCurrentFloorTick`).
    function _initializePoolKey() internal {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdc) < address(tmp) ? address(usdc) : address(tmp)),
            currency1: Currency.wrap(address(usdc) < address(tmp) ? address(tmp) : address(usdc)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        // address(this) == poolManager → onlyPoolManager modifier passes
        hook.beforeInitialize(address(this), key, 0);
    }

    function _setManagerToThis() internal {
        hook.setManager(address(this));
    }

    /* --------------------------------- defaults / immutables ------------------------- */

    function testDefaults() public view {
        assertEq(hook.baseDefenseTax(), 3_000);
        assertEq(hook.maxDefenseTax(), 500_000);
        assertEq(hook.taxRampTicks(), 4_080);
        assertEq(hook.owner(), owner);
        assertEq(hook.manager(), address(0));
        assertEq(hook.positionId(), 0);
        assertEq(address(hook.usdc()), address(usdc));
        assertEq(address(hook.tmp()), address(tmp));
        // poolKey populated by beforeInitialize
        (,, uint24 fee, int24 tickSpacing,) = hook.poolKey();
        assertEq(fee, LPFeeLibrary.DYNAMIC_FEE_FLAG);
        assertEq(tickSpacing, TICK_SPACING);
    }

    /* --------------------------------- setManager ------------------------------------ */

    function testSetManagerHappy() public {
        vm.expectEmit(false, false, false, true, address(hook));
        emit MoonpotHook.ManagerSet(managerAddr);
        hook.setManager(managerAddr);
        assertEq(hook.manager(), managerAddr);
    }

    function testSetManagerRevertsOnZero() public {
        vm.expectRevert(MoonpotHook.InvalidAddress.selector);
        hook.setManager(address(0));
    }

    function testSetManagerOnlyOnce() public {
        hook.setManager(managerAddr);
        vm.expectRevert(MoonpotHook.ManagerAlreadySet.selector);
        hook.setManager(address(0xC0FFEE));
    }

    function testSetManagerOnlyOwner() public {
        vm.expectRevert(); // OZ Ownable
        vm.prank(stranger);
        hook.setManager(managerAddr);
    }

    /* --------------------------------- setDefenseParams ------------------------------ */

    function testSetDefenseParamsHappy() public {
        vm.expectEmit(false, false, false, true, address(hook));
        emit MoonpotHook.DefenseParamsUpdated(1_000, 100_000, 8_000);
        hook.setDefenseParams(1_000, 100_000, 8_000);
        assertEq(hook.baseDefenseTax(), 1_000);
        assertEq(hook.maxDefenseTax(), 100_000);
        assertEq(hook.taxRampTicks(), 8_000);
    }

    function testSetDefenseParamsRevertsWhenBaseExceedsMax() public {
        vm.expectRevert(MoonpotHook.InvalidDefenseParams.selector);
        hook.setDefenseParams(500_001, 500_000, 1_000);
    }

    function testSetDefenseParamsRevertsWhenRampTicksZeroOrNegative() public {
        vm.expectRevert(MoonpotHook.InvalidDefenseParams.selector);
        hook.setDefenseParams(1_000, 100_000, 0);
        vm.expectRevert(MoonpotHook.InvalidDefenseParams.selector);
        hook.setDefenseParams(1_000, 100_000, -1);
    }

    function testSetDefenseParamsRevertsWhenMaxOver100Pct() public {
        vm.expectRevert(MoonpotHook.InvalidDefenseParams.selector);
        hook.setDefenseParams(1_000, 1_000_001, 1_000);
    }

    function testSetDefenseParamsBoundaryEqualMax() public {
        // base == max should be accepted (only base > max reverts)
        hook.setDefenseParams(500_000, 500_000, 1_000);
        assertEq(hook.baseDefenseTax(), 500_000);
        assertEq(hook.maxDefenseTax(), 500_000);
    }

    function testSetDefenseParamsOnlyOwner() public {
        vm.expectRevert();
        vm.prank(stranger);
        hook.setDefenseParams(1_000, 100_000, 1_000);
    }

    /* --------------------------------- setPositionId --------------------------------- */

    function testSetPositionIdHappy() public {
        _setManagerToThis();
        vm.expectEmit(false, false, false, true, address(hook));
        emit MoonpotHook.PositionIdSet(42);
        hook.setPositionId(42, -300, 300, 1_000_000);

        assertEq(hook.positionId(), 42);
        assertEq(hook.positionTickLower(), -300);
        assertEq(hook.positionTickUpper(), 300);
        assertEq(hook.protocolLiquidity(), 1_000_000);
    }

    function testSetPositionIdNoOpOnZero() public {
        _setManagerToThis();
        hook.setPositionId(0, -300, 300, 1_000_000);
        assertEq(hook.positionId(), 0);
        assertEq(hook.positionTickLower(), 0);
        assertEq(hook.positionTickUpper(), 0);
        assertEq(hook.protocolLiquidity(), 0);
    }

    function testSetPositionIdOnlyManager() public {
        _setManagerToThis();
        vm.expectRevert(MoonpotHook.OnlyManager.selector);
        vm.prank(stranger);
        hook.setPositionId(42, -300, 300, 1_000_000);
    }

    function testSetPositionIdRevertsBeforeManagerSet() public {
        vm.expectRevert(MoonpotHook.ManagerNotSet.selector);
        hook.setPositionId(42, -300, 300, 1_000_000);
    }

    /* --------------------------------- setCurrentFloorTick --------------------------- */

    function testSetCurrentFloorTickHappy() public {
        _setManagerToThis();
        vm.expectEmit(false, false, false, true, address(hook));
        emit MoonpotHook.CurrentFloorTickUpdated(1_500);
        hook.setCurrentFloorTick(1_500);

        assertEq(hook.currentFloorTick(), 1_500);
        assertEq(hook.floorTickLower(), 1_500 - TICK_SPACING);
        assertEq(hook.floorTickUpper(), 1_500 + TICK_SPACING);
    }

    function testSetCurrentFloorTickNegative() public {
        _setManagerToThis();
        hook.setCurrentFloorTick(-2_400);
        assertEq(hook.floorTickLower(), -2_400 - TICK_SPACING);
        assertEq(hook.floorTickUpper(), -2_400 + TICK_SPACING);
    }

    function testSetCurrentFloorTickOnlyManager() public {
        _setManagerToThis();
        vm.expectRevert(MoonpotHook.OnlyManager.selector);
        vm.prank(stranger);
        hook.setCurrentFloorTick(100);
    }

    function testSetCurrentFloorTickRevertsBeforeManagerSet() public {
        vm.expectRevert(MoonpotHook.ManagerNotSet.selector);
        hook.setCurrentFloorTick(100);
    }
}
