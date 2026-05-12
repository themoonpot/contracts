// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Fixtures.sol";

/// @notice Tests the Bernoulli NFT-allocation in `processBuy`. The math is:
///     for i in [0, tmpAmount):
///         keccak256(seed, i) % drawsLeft < nftsLeft  →  win (mint NFT)
///         drawsLeft--; if win, nftsLeft--
/// The seed comes from VRF; for our mock it's `keccak256(reqId, manager, 0)`.
contract MoonpotManagerProcessBuyTest is InitializedFixture {
    address buyer = address(0xBAB1);

    function _afterDeploy() internal override {
        usdc.transfer(buyer, 10_000_000e6);
        vm.prank(buyer);
        usdc.approve(address(mp), type(uint256).max);
    }

    function _commitAndDraw(uint256 tokens) internal returns (uint256 purchaseId, uint256 seed) {
        vm.prank(buyer);
        mp.buyFor(buyer, tokens * round1.PRICE(), 0, 0, bytes32(0), bytes32(0));
        purchaseId = mp.lastPurchaseId();
        uint256 reqId = vrf.latestRequestId();
        vrf.fulfill(reqId);
        (, , , , , seed, , , , ) = mp.purchases(purchaseId);
    }

    /// @dev Mirror of MoonpotManager.processBuy's Bernoulli loop.
    function _expectedNFTs(
        uint256 tmpAmount,
        uint256 seed,
        uint256 drawsLeft,
        uint32 nftsLeft
    ) internal pure returns (uint256 nftsFound) {
        for (uint256 i = 0; i < tmpAmount; i++) {
            if (nftsLeft == 0) break;
            uint256 check = uint256(keccak256(abi.encodePacked(seed, i)));
            if ((check % drawsLeft) < nftsLeft) {
                nftsFound++;
                nftsLeft--;
            }
            drawsLeft--;
        }
    }

    /* --------------------------------- happy path ----------------------------------- */

    function testProcessBuyMintsExpectedNFTCount() public {
        uint256 tokens = 100;
        (uint256 purchaseId, uint256 seed) = _commitAndDraw(tokens);

        uint256 expected = _expectedNFTs(
            tokens,
            seed,
            round1.TOTAL_TOKENS(),
            round1.TOTAL_NFTS()
        );

        uint256 nftBefore = nft.totalMinted();
        vm.expectEmit(true, true, true, true, address(mp));
        emit MoonpotManager.PurchaseFilled(1, purchaseId, buyer, expected);

        mp.processBuy(purchaseId);

        // NFTs minted to the buyer
        assertEq(nft.balanceOf(buyer), expected);
        assertEq(nft.totalMinted(), nftBefore + expected);

        // Round bookkeeping
        assertEq(round1.nftsMinted(), uint32(expected));
        assertEq(round1.scannedCount(), tokens);
        assertEq(mp.nftsMinted(), expected);

        // Purchase marked filled with the right count
        (, , uint256 nftAmount, , , , , , bool isDrawn, bool isFilled) = mp.purchases(purchaseId);
        assertTrue(isFilled);
        assertTrue(isDrawn);
        assertEq(nftAmount, expected);
    }

    function testProcessBuyDeterministicGivenFixedSeed() public {
        uint256 tokens = 200;
        (uint256 purchaseId, uint256 seed) = _commitAndDraw(tokens);
        // Re-derive expectation locally; same seed must always produce the same count
        uint256 expected = _expectedNFTs(tokens, seed, round1.TOTAL_TOKENS(), round1.TOTAL_NFTS());

        mp.processBuy(purchaseId);
        (, , uint256 nftAmount, , , , , , , ) = mp.purchases(purchaseId);
        assertEq(nftAmount, expected);
    }

    function testProcessBuyAlwaysMarksScannedEvenWithZeroNFTs() public {
        // With a tiny purchase, the chance of winning an NFT is small but the
        // scanned counter should reflect tmpAmount regardless.
        uint256 tokens = 1;
        (uint256 purchaseId, ) = _commitAndDraw(tokens);

        uint256 scannedBefore = round1.scannedCount();
        mp.processBuy(purchaseId);
        assertEq(round1.scannedCount(), scannedBefore + tokens);
    }

    function testProcessBuyIsCallableByAnyone() public {
        (uint256 purchaseId, ) = _commitAndDraw(50);
        vm.prank(address(0xDEAD));
        mp.processBuy(purchaseId);
        (, , , , , , , , , bool isFilled) = mp.purchases(purchaseId);
        assertTrue(isFilled);
    }

    /* --------------------------------- revert paths --------------------------------- */

    function testProcessBuyRevertsWhenSeedNotDrawn() public {
        // Commit but do NOT fulfill VRF
        vm.prank(buyer);
        mp.buyFor(buyer, 50 * round1.PRICE(), 0, 0, bytes32(0), bytes32(0));
        uint256 purchaseId = mp.lastPurchaseId();

        vm.expectRevert(MoonpotManager.SeedNotDrawn.selector);
        mp.processBuy(purchaseId);
    }

    function testProcessBuyRevertsOnUnknownPurchase() public {
        // purchaseId 9999 has buyer == address(0)
        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        mp.processBuy(9999);
    }

    function testProcessBuyRevertsOnSecondCall() public {
        (uint256 purchaseId, ) = _commitAndDraw(20);
        mp.processBuy(purchaseId);
        vm.expectRevert(MoonpotManager.AlreadyFilled.selector);
        mp.processBuy(purchaseId);
    }

    /* --------------------------------- edge: zero allocations ------------------------ */

    function testProcessBuyWhenRoundHasNoNFTsLeftMintsZero() public {
        // Drain NFTs from the round (impersonate the manager).
        uint32 totalNfts = round1.TOTAL_NFTS();
        vm.prank(address(mp));
        round1.notifyNFTMinted(totalNfts);

        // Commit + fulfill a small buy
        (uint256 purchaseId, ) = _commitAndDraw(10);

        mp.processBuy(purchaseId);

        // No NFTs minted to buyer; scanned still increments
        assertEq(nft.balanceOf(buyer), 0);
        (, , uint256 nftAmount, , , , , , , bool isFilled) = mp.purchases(purchaseId);
        assertEq(nftAmount, 0);
        assertTrue(isFilled);
        assertEq(round1.scannedCount(), 10);
    }
}
