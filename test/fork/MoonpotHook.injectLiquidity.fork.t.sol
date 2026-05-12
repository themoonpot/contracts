// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./ForkFixture.sol";

/// @notice Fork tests for the manager-triggered `hook.injectLiquidity` path.
/// Exercises the full chain: `manager.buyFor` crosses the 25k-token checkpoint
/// → `_maybeInjectLiquidity` mints matching TMP and calls `hook.injectLiquidity`
/// → hook calls `poolManager.unlock` → `unlockCallback` runs
/// `positionManager.modifyLiquiditiesWithoutUnlock(INCREASE_LIQUIDITY)` on the
/// real Base v4 position. Asserts the protocol LP actually grew.
contract MoonpotHookInjectLiquidityForkTest is ForkFixture {
    address buyer = address(0xBABA);

    function _afterInit() internal override {
        // Fund the buyer with enough USDC to cross the first 25k checkpoint.
        // Round 1: price $1.15, max purchase 10_000 tokens per call. Three buys
        // of 9_000 tokens each = 27_000 tokens at $1.15 = $31_050 USDC.
        deal(USDC, buyer, 100_000e6);
        vm.prank(buyer);
        (bool ok, ) = USDC.call(
            abi.encodeWithSignature("approve(address,uint256)", address(mp), type(uint256).max)
        );
        require(ok, "usdc approve failed");
    }

    function _buy(uint256 tokens) internal {
        uint256 usdcAmount = tokens * round1.PRICE();
        vm.prank(buyer);
        mp.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));
    }

    function testInjectionCrossesFirstCheckpointAgainstRealV4() public {
        uint128 liquidityBefore = hook.protocolLiquidity();
        assertGt(liquidityBefore, 0, "init seeded the LP");
        assertEq(mp.lastInjectionCheckpoint(1), 0);
        assertEq(mp.pendingLiquidityUsdc(), 0);

        // Two buys: 9_000 + 9_000 = 18_000 (no crossing yet)
        _buy(9_000);
        _buy(9_000);

        assertEq(mp.lastInjectionCheckpoint(1), 0, "no crossing yet");
        assertEq(mp.pendingLiquidityUsdc(), 18_000 * 0.05e6, "pending accumulates");

        // Third buy: 9_000 → tokensSold = 27_000, crosses 25_000 checkpoint
        _buy(9_000);

        assertEq(mp.lastInjectionCheckpoint(1), 27_000, "checkpoint advanced");
        assertEq(mp.pendingLiquidityUsdc(), 0, "pending drained by injection");

        // Hook's `protocolLiquidity` increased; proves the real
        // PositionManager.INCREASE_LIQUIDITY call actually executed against
        // the real v4 pool.
        assertGt(hook.protocolLiquidity(), liquidityBefore, "LP position grew");

        // The injected position's liquidity (queryable from PositionManager)
        // should match `hook.protocolLiquidity` exactly; proves the hook's
        // bookkeeping mirrors the on-chain truth.
        (bool ok, bytes memory ret) = address(positionManager).staticcall(
            abi.encodeWithSignature("getPositionLiquidity(uint256)", hook.positionId())
        );
        require(ok && ret.length == 32, "getPositionLiquidity failed");
        uint128 onChainLiquidity = abi.decode(ret, (uint128));
        assertEq(uint256(hook.protocolLiquidity()), uint256(onChainLiquidity), "hook tracks on-chain LP");
    }

    function testNoInjectionBelowCheckpoint() public {
        uint128 liquidityBefore = hook.protocolLiquidity();
        _buy(10_000);
        _buy(10_000);

        // Below the 25k threshold; injection should NOT fire
        assertEq(mp.lastInjectionCheckpoint(1), 0);
        assertEq(mp.pendingLiquidityUsdc(), 20_000 * 0.05e6);
        assertEq(hook.protocolLiquidity(), liquidityBefore, "LP unchanged");
    }
}
