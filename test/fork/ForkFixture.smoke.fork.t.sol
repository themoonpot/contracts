// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./ForkFixture.sol";

contract ForkFixtureSmokeTest is ForkFixture {
    function testForkSetupSucceeded() public view {
        // If the fork wasn't available, setUp would have skipped this test.
        assertTrue(mp.isInitialized(), "manager initialized");
        assertEq(mp._currentRoundId(), 1, "round 1 active");

        // Hook armed with a real position from the real PositionManager
        assertGt(hook.positionId(), 0, "real position minted");
        assertGt(hook.protocolLiquidity(), 0, "non-zero LP");
        assertGt(hook.positionTickUpper(), hook.positionTickLower(), "position has range");

        // Pool initialized with the right pair of currencies
        (Currency c0, Currency c1, , int24 tickSpacing, ) = hook.poolKey();
        address t0 = Currency.unwrap(c0);
        address t1 = Currency.unwrap(c1);
        assertTrue(
            (t0 == USDC && t1 == address(tmp)) || (t0 == address(tmp) && t1 == USDC),
            "pool key wires USDC + TMP"
        );
        assertEq(tickSpacing, 60, "tickSpacing 60");
    }
}
