// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Fixtures.sol";

/// @notice Tests for MoonpotManager's `fulfillRandomWords` VRF callback
/// dispatcher: it must route by `VRFRequestType` (Purchase vs Round) and
/// be idempotent on re-fulfillment.
contract MoonpotManagerVRFTest is InitializedFixture {
    address buyer = address(0xBAB1);

    function _afterDeploy() internal override {
        usdc.transfer(buyer, 10_000_000e6);
        vm.prank(buyer);
        usdc.approve(address(mp), type(uint256).max);
    }

    function _commitPurchase(uint256 tokens) internal returns (uint256 reqId, uint256 purchaseId) {
        uint256 reqIdBefore = vrf.latestRequestId();
        vm.prank(buyer);
        mp.buyFor(buyer, tokens * round1.PRICE(), 0, 0, bytes32(0), bytes32(0));
        reqId = vrf.latestRequestId();
        purchaseId = mp.lastPurchaseId();
        // Sanity: incremented
        require(reqId == reqIdBefore + 1, "no new req");
    }

    /* --------------------------- Purchase fulfillment ------------------------------- */

    function testFulfillPurchaseSetsSeedAndMarksDrawn() public {
        (uint256 reqId, uint256 purchaseId) = _commitPurchase(50);

        vm.expectEmit(true, true, true, false, address(mp));
        emit MoonpotManager.PurchaseSeedDrawn(1, purchaseId, buyer, 0);

        vrf.fulfill(reqId);

        (
            , , , , ,
            uint256 seed,
            , , bool isDrawn, bool isFilled
        ) = mp.purchases(purchaseId);
        assertTrue(isDrawn, "purchase not marked drawn");
        assertFalse(isFilled, "purchase should not yet be filled");
        assertGt(seed, 0, "seed should be set");
    }

    function testFulfillPurchaseClearsVrfBookkeeping() public {
        (uint256 reqId, ) = _commitPurchase(50);
        vrf.fulfill(reqId);

        // After fulfillment the manager deletes its vrf<->id mappings
        assertEq(uint256(mp.vrfRequestType(reqId)), 0); // VRFRequestType.None
        assertEq(mp.vrfToId(reqId), 0);
    }

    function testFulfillPurchaseIdempotentOnSecondCall() public {
        (uint256 reqId, uint256 purchaseId) = _commitPurchase(50);

        vrf.fulfill(reqId);
        (, , , , , uint256 seed1, , , bool isDrawn1, ) = mp.purchases(purchaseId);

        // Manually re-fulfill via low-level call (mock deletes the req after success)
        // Use vm.prank as vrf coordinator + the manager's rawFulfillRandomWords path
        uint256[] memory words = new uint256[](1);
        words[0] = uint256(0xC0FFEE);
        vm.prank(address(vrf));
        // The manager's check is `if (p.buyer == address(0) || p.isDrawn) return;`;
        // so a second call returns silently without overwriting state.
        (bool ok, ) = address(mp).call(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", reqId, words)
        );
        assertTrue(ok, "second fulfill should not revert");

        (, , , , , uint256 seed2, , , bool isDrawn2, ) = mp.purchases(purchaseId);
        assertEq(seed1, seed2, "seed must not change on re-fulfillment");
        assertTrue(isDrawn2);
    }

    function testFulfillPurchaseUnknownReqIsSilentNoOp() public {
        // Manager hasn't seen this reqId; dispatch falls through (VRFRequestType.None)
        uint256[] memory words = new uint256[](1);
        words[0] = 42;
        vm.prank(address(vrf));
        (bool ok, ) = address(mp).call(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", uint256(9999), words)
        );
        assertTrue(ok, "unknown reqId should be silently ignored");
    }

    /* ---------------------------- Round fulfillment --------------------------------- */

    function testFulfillRoundSetsRoundSeed() public {
        // End the round manually as the manager (skipping the sellout path so
        // we don't have to cross liquidity-injection checkpoints).
        vm.prank(address(mp));
        round1.end();

        // Trigger a fresh VRF round-reveal request via retryRoundReveal
        uint256 reqIdBefore = vrf.latestRequestId();
        mp.retryRoundReveal(1);
        uint256 reqId = vrf.latestRequestId();
        assertEq(reqId, reqIdBefore + 1);
        assertEq(uint256(mp.vrfRequestType(reqId)), 2); // VRFRequestType.Round

        vm.expectEmit(true, false, false, false, address(mp));
        emit MoonpotManager.RoundRevealed(1, 0);
        vrf.fulfill(reqId);

        assertGt(round1.seed(), 0);
    }

    function testFulfillRoundClearsVrfBookkeeping() public {
        vm.prank(address(mp));
        round1.end();
        mp.retryRoundReveal(1);
        uint256 reqId = vrf.latestRequestId();

        vrf.fulfill(reqId);
        assertEq(uint256(mp.vrfRequestType(reqId)), 0);
        assertEq(mp.vrfToId(reqId), 0);
    }

    function testFulfillFromNonCoordinatorReverts() public {
        // Chainlink's `VRFConsumerBaseV2Plus.rawFulfillRandomWords` checks
        // msg.sender == s_vrfCoordinator and reverts otherwise.
        (uint256 reqId, ) = _commitPurchase(10);
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vm.expectRevert();
        vm.prank(address(0xBAD));
        (bool ok, ) = address(mp).call(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", reqId, words)
        );
        // The call itself succeeds at the EVM level (call returns false on revert),
        // so we don't assert ok; only that the prank+revert pattern matches.
        ok; // silence unused warning
    }
}
