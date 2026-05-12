// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Fixtures.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @notice Tests for `_maybeInjectLiquidity`; the per-buyFor checkpoint that
/// pushes accumulated USDC into the LP every 1/40 of a round's supply.
///
/// The hook's actual `injectLiquidity` is mocked here (it goes through
/// `poolManager.unlock` → `unlockCallback` → real v4 LP mint, which our stub
/// PoolManager doesn't support). `poolManager.extsload` is mocked to return a
/// canned slot0 so `_maybeInjectLiquidity` can read the sqrtPriceX96.
contract MoonpotManagerLiquidityInjectionTest is InitializedFixture {
    using PoolIdLibrary for PoolKey;

    address buyer = address(0xBAB1);

    function _afterDeploy() internal override {
        usdc.transfer(buyer, 100_000_000e6);
        vm.prank(buyer);
        usdc.approve(address(mp), type(uint256).max);

        // Mock pool slot0 so `_maybeInjectLiquidity` gets a valid sqrtPriceX96.
        // We pick a sqrtPriceX96 inside the position range (between
        // positionTickLower and positionTickUpper).
        _setMockSlot0(TickMath.getSqrtPriceAtTick(-260_000));

        // Mock hook.injectLiquidity so the manager's call doesn't enter the
        // unlock-callback path against our stub PoolManager.
        vm.mockCall(
            address(hook),
            abi.encodeWithSelector(MoonpotHook.injectLiquidity.selector),
            bytes("")
        );
    }

    function _setMockSlot0(uint160 sqrtPriceX96) internal {
        // StateLibrary.getSlot0 reads `extsload(_getPoolStateSlot(poolId))` and
        // unpacks the low 160 bits as sqrtPriceX96. We mock all extsload calls
        // on the pool manager to return this packed value.
        bytes32 slot0 = bytes32(uint256(sqrtPriceX96));
        vm.mockCall(
            address(poolManager),
            abi.encodeWithSignature("extsload(bytes32)"),
            abi.encode(slot0)
        );
    }

    function _buy(uint256 tokens) internal {
        vm.prank(buyer);
        mp.buyFor(buyer, tokens * round1.PRICE(), 0, 0, bytes32(0), bytes32(0));
    }

    /* --------------------- below threshold: no injection ----------------------------- */

    function testNoInjectionBelowThreshold() public {
        // Round 1: 1M tokens, interval = 25,000. Buying 10,000 keeps us at
        // checkpoint 0 / interval 0; early return fires.
        _buy(10_000);

        // pendingLiquidityUsdc accumulates without being drained
        assertEq(mp.pendingLiquidityUsdc(), 10_000 * 0.05e6);
        assertEq(mp.lastInjectionCheckpoint(1), 0);
    }

    function testNoInjectionBelowSingleIntervalBoundary() public {
        _buy(10_000);
        _buy(10_000);
        // 20k sold; 20k / 25k = 0 (same as checkpoint/interval = 0) → no inject
        assertEq(mp.lastInjectionCheckpoint(1), 0);
        assertEq(mp.pendingLiquidityUsdc(), 20_000 * 0.05e6);
    }

    /* --------------------- crossing the first 25k checkpoint ------------------------- */

    function testInjectionFiresAfterFirstCheckpointCrossing() public {
        // Buy 25,000 + 1 tokens in three steps; the 25k crossing triggers
        // an injection at the last buy.
        _buy(10_000);
        _buy(10_000);
        // Third buy: 5_001; crosses 25_000
        _buy(5_001);

        // Checkpoint advanced and pending drained
        assertEq(mp.lastInjectionCheckpoint(1), 25_001);
        assertEq(mp.pendingLiquidityUsdc(), 0);
    }

    function testInjectionCallsHookWithFullPending() public {
        // We can't verify the hook.injectLiquidity arg directly because vm.mockCall
        // doesn't expose call history. But we CAN check side-effects:
        //   - manager minted TMP to the hook (`tmp.mint(address(hook), tmpAmount)`)
        //   - pendingLiquidityUsdc reset to 0
        uint256 hookTmpBefore = tmp.balanceOf(address(hook));

        _buy(10_000);
        _buy(10_000);
        _buy(5_001);

        // TMP supply increased (manager minted to hook)
        assertGt(tmp.balanceOf(address(hook)), hookTmpBefore);
        // Pending drained
        assertEq(mp.pendingLiquidityUsdc(), 0);
    }

    function testInjectionEmitsPendingLiquidityUpdated() public {
        _buy(10_000);
        _buy(10_000);
        // Last buy: expect TWO PendingLiquidityUpdated emits; first when the
        // liquidity share is added (5_001 * 0.05e6 = 250_050_000), then again
        // when the injection drains to 0.
        vm.recordLogs();
        _buy(5_001);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("PendingLiquidityUpdated(uint256)");
        uint256 count;
        uint256 lastValue;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == sig && logs[i].emitter == address(mp)) {
                count++;
                lastValue = abi.decode(logs[i].data, (uint256));
            }
        }
        assertEq(count, 2, "expected two emits");
        assertEq(lastValue, 0, "last emit should be 0 after injection");
    }

    /* --------------------- subsequent checkpoints --------------------------------- */

    function testInjectionAtEverySubsequentCheckpoint() public {
        // First crossing
        _buy(10_000);
        _buy(10_000);
        _buy(5_001);
        assertEq(mp.lastInjectionCheckpoint(1), 25_001);

        // Within the same interval (between 25k and 50k); no further injection
        _buy(10_000);
        assertEq(mp.lastInjectionCheckpoint(1), 25_001);
        assertEq(mp.pendingLiquidityUsdc(), 10_000 * 0.05e6);

        // Crossing the 50k checkpoint
        _buy(10_000);
        _buy(5_000);
        assertEq(mp.lastInjectionCheckpoint(1), 50_001);
        assertEq(mp.pendingLiquidityUsdc(), 0);
    }

}
