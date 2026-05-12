// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Fixtures.sol";

contract BaseFixtureSmokeTest is BaseFixture {
    function testWiringIsCorrect() public view {
        assertEq(address(tmp.manager()), address(mp));
        assertEq(address(nft.manager()), address(mp));
        assertEq(hook.manager(), address(mp));
        assertEq(address(mp.rounds(1)), address(round1));
        assertEq(address(mp.rounds(5)), address(round5));
        assertEq(mp.company(), COMPANY);
        assertFalse(mp.isInitialized());
        assertEq(mp._currentRoundId(), 0);
    }
}

contract InitializedFixtureSmokeTest is InitializedFixture {
    function testInitState() public view {
        assertTrue(mp.isInitialized());
        assertEq(mp._currentRoundId(), 1);

        // Hook armed with position info from init
        assertEq(hook.positionId(), 1);
        assertGt(hook.protocolLiquidity(), 0);
        assertGt(hook.positionTickUpper(), hook.positionTickLower());

        // Round 1 started
        assertGt(round1.startTime(), 0);
        assertLt(round1.startTime(), type(uint256).max);
        assertEq(round1.endTime(), 0);
    }
}
