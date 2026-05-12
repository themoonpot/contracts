// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Fixtures.sol";

contract MoonpotManagerBuyForTest is InitializedFixture {
    address buyer = address(0xBAB1);

    function _afterDeploy() internal override {
        // Fund buyer with USDC and pre-approve the manager
        usdc.transfer(buyer, 10_000_000e6);
        vm.prank(buyer);
        usdc.approve(address(mp), type(uint256).max);
    }

    /* ---------------------------------- happy path ----------------------------------- */

    function testBuyForHappyPath() public {
        uint256 tokens = 100;
        uint256 price = round1.PRICE(); // 1.15e6
        uint256 usdcAmount = tokens * price;

        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);
        uint256 companyUsdcBefore = usdc.balanceOf(COMPANY);
        uint256 roundUsdcBefore = usdc.balanceOf(address(round1));
        uint256 hookUsdcBefore = usdc.balanceOf(address(hook));

        vm.expectEmit(true, true, true, true, address(mp));
        emit MoonpotManager.PurchaseCommitted(1, 1, buyer, tokens);

        vm.prank(buyer);
        mp.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));

        // USDC routing: company gets 0.10 per token, round gets 1.00 per token,
        // hook gets 0.05 per token.
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore - usdcAmount);
        assertEq(usdc.balanceOf(COMPANY), companyUsdcBefore + tokens * 0.10e6);
        assertEq(usdc.balanceOf(address(round1)), roundUsdcBefore + tokens * 1.00e6);
        assertEq(usdc.balanceOf(address(hook)), hookUsdcBefore + tokens * 0.05e6);

        // TMP mint to buyer at tokens * 1e18
        assertEq(tmp.balanceOf(buyer), tokens * 1e18);

        // Round bookkeeping: rewardPool += community share, tokensSold += tokens
        assertEq(round1.rewardPool(), tokens * 1.00e6);
        assertEq(round1.tokensSold(), tokens);

        // Manager bookkeeping
        assertEq(mp.pendingLiquidityUsdc(), tokens * 0.05e6);
        assertEq(mp.tokensSold(), tokens);
        assertEq(mp.lastPurchaseId(), 1);

        // Purchase record stored
        (
            address pBuyer,
            uint256 tmpAmount,
            uint256 nftAmount,
            uint256 roundId,
            ,
            uint256 seed,
            ,
            uint32 nftsMintedBefore,
            bool isDrawn,
            bool isFilled
        ) = mp.purchases(1);
        assertEq(pBuyer, buyer);
        assertEq(tmpAmount, tokens);
        assertEq(nftAmount, 0);
        assertEq(roundId, 1);
        assertEq(seed, 0);
        assertEq(nftsMintedBefore, 0);
        assertFalse(isDrawn);
        assertFalse(isFilled);
    }

    function testBuyForRequestsVRFAndMarksTypePurchase() public {
        uint256 tokens = 50;
        uint256 usdcAmount = tokens * round1.PRICE();

        uint256 vrfReqIdBefore = vrf.latestRequestId();
        vm.prank(buyer);
        mp.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));

        // VRF coordinator issued exactly one new request
        uint256 vrfReqIdAfter = vrf.latestRequestId();
        assertEq(vrfReqIdAfter, vrfReqIdBefore + 1);

        // Manager linked this request to purchase id 1 with VRFRequestType.Purchase (= 1)
        assertEq(uint256(mp.vrfRequestType(vrfReqIdAfter)), 1);
        assertEq(mp.vrfToId(vrfReqIdAfter), 1);
    }

    function testBuyForMultiplePurchasesIncrementsIds() public {
        uint256 usdcAmount = 50 * round1.PRICE();
        vm.startPrank(buyer);
        mp.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));
        mp.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));
        mp.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));
        vm.stopPrank();

        assertEq(mp.lastPurchaseId(), 3);
        assertEq(round1.tokensSold(), 150);
        assertEq(mp.tokensSold(), 150);
    }

    /* ---------------------------------- revert paths --------------------------------- */

    function testBuyForRevertsWhenAmountNotMultipleOfPrice() public {
        uint256 price = round1.PRICE(); // 1.15e6
        // Pay 1 USDC less than 100 × price; not a multiple
        vm.prank(buyer);
        vm.expectRevert(MoonpotManager.IncorrectAmount.selector);
        mp.buyFor(buyer, 100 * price - 1, 0, 0, bytes32(0), bytes32(0));
    }

    function testBuyForRevertsBelowOneTokenWorth() public {
        uint256 price = round1.PRICE();
        vm.prank(buyer);
        vm.expectRevert(MoonpotManager.IncorrectAmount.selector);
        mp.buyFor(buyer, price - 1, 0, 0, bytes32(0), bytes32(0));
    }

    function testBuyForRevertsOnMaxPurchaseLimit() public {
        // 10_001 tokens exceeds MAX_PURCHASE_LIMIT = 10_000
        uint256 usdcAmount = 10_001 * round1.PRICE();
        vm.prank(buyer);
        vm.expectRevert(MoonpotManager.MaxPurchaseLimitExceeded.selector);
        mp.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));
    }

    function testBuyForRevertsWhenInsufficientTokensRemainInRound() public {
        // Round 1 has 1,000,000 tokens. Drain to 50 remaining as the manager
        // (single pranked call; `vm.prank` only sticks for ONE call).
        uint256 toSell = round1.TOTAL_TOKENS() - 50;
        vm.prank(address(mp));
        round1.notifyPurchase(toSell);

        uint256 usdcAmount = 100 * round1.PRICE();
        vm.prank(buyer);
        vm.expectRevert(MoonpotManager.TokenSupplyNotEnough.selector);
        mp.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));
    }

    function testBuyForRevertsWhenRoundSoldOut() public {
        uint256 toSell = round1.TOTAL_TOKENS();
        vm.prank(address(mp));
        round1.notifyPurchase(toSell);

        uint256 usdcAmount = round1.PRICE(); // 1 token
        vm.prank(buyer);
        vm.expectRevert(MoonpotManager.RoundSoldOut.selector);
        mp.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));
    }

    function testBuyForRevertsBeforeRoundStarted() public {
        // Use BaseFixture state: deploy a fresh manager that hasn't called start()
        MoonpotManager mp2 = new MoonpotManager(
            address(usdc),
            address(tmp),
            address(nft),
            COMPANY,
            address(vrf),
            VRF_KEY,
            VRF_SUB,
            address(poolManager),
            positionManager,
            address(permit2),
            address(hook)
        );

        // Wire round1 but not start()
        MoonpotRound1 r1 = new MoonpotRound1(address(mp2), address(usdc));
        mp2.setRound(1, address(r1));

        // _validateRound revert because _currentRoundId == 0 and rounds[0] == 0
        uint256 usdcAmount = round1.PRICE();
        vm.prank(buyer);
        vm.expectRevert(MoonpotManager.RoundNotActive.selector);
        mp2.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));
    }

    function testBuyForRevertsAfterRoundEnded() public {
        // End round 1 manually (as the manager) to simulate post-sellout state.
        // _validateRound checks round.getEndTime() != 0 → RoundNotActive.
        vm.prank(address(mp));
        round1.end();

        uint256 usdcAmount = round1.PRICE();
        vm.prank(buyer);
        vm.expectRevert(MoonpotManager.RoundNotActive.selector);
        mp.buyFor(buyer, usdcAmount, 0, 0, bytes32(0), bytes32(0));
    }
}
