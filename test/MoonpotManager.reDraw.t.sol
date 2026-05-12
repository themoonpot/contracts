// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Fixtures.sol";

/// @notice Tests `reDrawPurchase`: re-requests a VRF word for a stuck
/// (un-fulfilled) purchase. Non-owners must wait `VRF_TIMEOUT = 24h` since the
/// previous request; the owner can re-request immediately. A purchase whose
/// seed has already been drawn rejects re-draw with `AlreadySeeded`.
contract MoonpotManagerReDrawTest is InitializedFixture {
    address buyer = address(0xBAB1);
    address stranger = address(0xBAD);

    function _afterDeploy() internal override {
        usdc.transfer(buyer, 10_000_000e6);
        vm.prank(buyer);
        usdc.approve(address(mp), type(uint256).max);
    }

    function _commitOnly(uint256 tokens) internal returns (uint256 purchaseId, uint256 reqId) {
        vm.prank(buyer);
        mp.buyFor(buyer, tokens * round1.PRICE(), 0, 0, bytes32(0), bytes32(0));
        purchaseId = mp.lastPurchaseId();
        reqId = vrf.latestRequestId();
    }

    /* --------------------------- owner reDraw (no wait) ------------------------------ */

    function testOwnerCanReDrawImmediately() public {
        (uint256 purchaseId, uint256 oldReqId) = _commitOnly(10);

        vm.expectEmit(true, false, false, false, address(mp));
        emit MoonpotManager.PurchaseReDrawn(purchaseId, 0);
        mp.reDrawPurchase(purchaseId);

        uint256 newReqId = vrf.latestRequestId();
        assertGt(newReqId, oldReqId, "new request id should be issued");
        assertEq(uint256(mp.vrfRequestType(newReqId)), 1); // Purchase
        assertEq(mp.vrfToId(newReqId), purchaseId);
    }

    function testOwnerReDrawUpdatesRequestTimestamp() public {
        (uint256 purchaseId, ) = _commitOnly(10);
        uint256 initialTs;
        ( , , , , initialTs, , , , , ) = mp.purchases(purchaseId);

        vm.warp(block.timestamp + 1 hours);
        mp.reDrawPurchase(purchaseId);

        uint256 newTs;
        ( , , , , newTs, , , , , ) = mp.purchases(purchaseId);
        assertEq(newTs, initialTs + 1 hours);
    }

    /* --------------------------- non-owner: must wait 24h --------------------------- */

    function testNonOwnerReDrawRevertsBeforeTimeout() public {
        (uint256 purchaseId, ) = _commitOnly(10);

        vm.warp(block.timestamp + 23 hours);
        vm.expectRevert(MoonpotManager.RetryTooEarly.selector);
        vm.prank(stranger);
        mp.reDrawPurchase(purchaseId);
    }

    function testNonOwnerReDrawSucceedsAfterTimeout() public {
        (uint256 purchaseId, uint256 oldReqId) = _commitOnly(10);

        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(stranger);
        mp.reDrawPurchase(purchaseId);

        uint256 newReqId = vrf.latestRequestId();
        assertGt(newReqId, oldReqId);
    }

    /* --------------------------- AlreadySeeded after fulfill ------------------------- */

    function testReDrawRevertsAfterPurchaseSeedDrawn() public {
        (uint256 purchaseId, uint256 reqId) = _commitOnly(10);
        vrf.fulfill(reqId);

        vm.expectRevert(MoonpotManager.AlreadySeeded.selector);
        mp.reDrawPurchase(purchaseId);
    }

    /* --------------------------- unknown purchase ------------------------------------ */

    function testReDrawRevertsOnUnknownPurchase() public {
        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        mp.reDrawPurchase(9999);
    }
}
