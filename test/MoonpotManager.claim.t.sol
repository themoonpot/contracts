// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Fixtures.sol";
import "../contracts/IMoonpotRound.sol";

/// @notice End-to-end claim tests: buy → VRF fulfill → processBuy → round end →
/// round seed → claimNFT / claimNFTs.
contract MoonpotManagerClaimTest is InitializedFixture {
    address buyer = address(0xBAB1);
    address stranger = address(0xBAD);

    function _afterDeploy() internal override {
        usdc.transfer(buyer, 10_000_000e6);
        vm.prank(buyer);
        usdc.approve(address(mp), type(uint256).max);
    }

    /// @dev Buy `tokens` worth, fulfill the VRF, run processBuy. Returns
    /// the tokenIds the buyer received.
    function _buyAndProcess(uint256 tokens) internal returns (uint256[] memory tokenIds) {
        uint256 nftBefore = nft.balanceOf(buyer);

        vm.prank(buyer);
        mp.buyFor(buyer, tokens * round1.PRICE(), 0, 0, bytes32(0), bytes32(0));
        uint256 purchaseId = mp.lastPurchaseId();

        vrf.fulfill(vrf.latestRequestId());
        mp.processBuy(purchaseId);

        uint256 minted = nft.balanceOf(buyer) - nftBefore;
        tokenIds = nft.tokensOfOwnerIn(buyer, nftBefore, nftBefore + minted);
    }

    /// @dev End round-1 and inject a seed (acting as the manager).
    function _endAndSeedRound1(uint256 seed) internal {
        vm.startPrank(address(mp));
        round1.end();
        round1.setSeed(seed);
        vm.stopPrank();
    }

    /* --------------------------------- happy paths ----------------------------------- */

    function testClaimNFTTransfersRewardAndMarksClaimed() public {
        // Buy a lot so we're virtually guaranteed at least one NFT
        uint256[] memory ids = _buyAndProcess(500);
        require(ids.length > 0, "needs at least one NFT");
        uint256 tokenId = ids[0];

        _endAndSeedRound1(0xC0FFEE);

        (uint256 value, uint8 classId, ) = round1.valueOf(tokenId);

        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);
        uint256 roundUsdcBefore = usdc.balanceOf(address(round1));

        vm.expectEmit(true, true, true, true, address(mp));
        emit MoonpotManager.NFTClaimed(1, tokenId, classId, value);

        vm.prank(buyer);
        mp.claimNFT(tokenId);

        // USDC moved from round to buyer
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore + value);
        assertEq(usdc.balanceOf(address(round1)), roundUsdcBefore - value);

        // Marked claimed
        assertTrue(mp.claimed(1, tokenId));
        // Round bookkeeping
        assertEq(round1.rewardPool(), (500 * 1.00e6) - value);
    }

    function testClaimNFTsBatchesByRound() public {
        // Buy enough that some tokens land in any tier; claim a batch of up to 3.
        uint256[] memory ids = _buyAndProcess(1000);
        require(ids.length >= 2, "need at least 2 NFTs for batch test");

        _endAndSeedRound1(0xABC);

        uint256 batchSize = ids.length >= 3 ? 3 : 2;
        uint256[] memory batch = new uint256[](batchSize);
        uint256 expectedTotal;
        for (uint256 i = 0; i < batchSize; i++) {
            batch[i] = ids[i];
            (uint256 v, , ) = round1.valueOf(ids[i]);
            expectedTotal += v;
        }

        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);

        vm.prank(buyer);
        mp.claimNFTs(batch);

        // Buyer received the combined value
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore + expectedTotal);
        for (uint256 i = 0; i < batchSize; i++) {
            assertTrue(mp.claimed(1, batch[i]));
        }
    }

    function testClaimNFTsEmptyArrayNoOp() public {
        // No revert, no state change
        uint256[] memory empty = new uint256[](0);
        vm.prank(buyer);
        mp.claimNFTs(empty);
    }

    /* --------------------------------- revert paths --------------------------------- */

    function testClaimRevertsWhenNotOwner() public {
        uint256[] memory ids = _buyAndProcess(500);
        require(ids.length > 0);
        _endAndSeedRound1(0xC0FFEE);

        vm.expectRevert(MoonpotManager.NotOwner.selector);
        vm.prank(stranger);
        mp.claimNFT(ids[0]);
    }

    function testClaimRevertsWhenRoundNotEnded() public {
        uint256[] memory ids = _buyAndProcess(500);
        require(ids.length > 0);
        // Round1 not ended yet
        vm.expectRevert(MoonpotManager.RoundNotEnded.selector);
        vm.prank(buyer);
        mp.claimNFT(ids[0]);
    }

    function testClaimRevertsWhenRoundNotSeeded() public {
        uint256[] memory ids = _buyAndProcess(500);
        require(ids.length > 0);
        // End but do NOT seed
        vm.prank(address(mp));
        round1.end();

        vm.expectRevert(MoonpotManager.RoundNotSeeded.selector);
        vm.prank(buyer);
        mp.claimNFT(ids[0]);
    }

    function testClaimRevertsOnSecondClaim() public {
        uint256[] memory ids = _buyAndProcess(500);
        require(ids.length > 0);
        _endAndSeedRound1(0xC0FFEE);

        vm.prank(buyer);
        mp.claimNFT(ids[0]);

        vm.expectRevert(MoonpotManager.AlreadyClaimed.selector);
        vm.prank(buyer);
        mp.claimNFT(ids[0]);
    }

    function testClaimNFTsRevertsIfAnyTokenNotOwned() public {
        uint256[] memory ids = _buyAndProcess(500);
        require(ids.length >= 2);
        _endAndSeedRound1(0xC0FFEE);

        // Transfer one token away mid-batch
        vm.prank(buyer);
        nft.transferFrom(buyer, stranger, ids[1]);

        vm.expectRevert(MoonpotManager.NotOwner.selector);
        vm.prank(buyer);
        mp.claimNFTs(ids);
    }

    function testClaimNFTsRevertsIfAlreadyClaimedMidBatch() public {
        uint256[] memory ids = _buyAndProcess(500);
        require(ids.length >= 2);
        _endAndSeedRound1(0xC0FFEE);

        // Single-claim ids[0] first
        vm.prank(buyer);
        mp.claimNFT(ids[0]);

        // Now batch-claim including ids[0] → AlreadyClaimed
        vm.expectRevert(MoonpotManager.AlreadyClaimed.selector);
        vm.prank(buyer);
        mp.claimNFTs(ids);
    }
}
