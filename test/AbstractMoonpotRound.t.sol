// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/MoonpotRound1.sol";
import "../contracts/AbstractMoonpotRound.sol";
import "../contracts/mocks/MockUSDC.sol";

contract AbstractMoonpotRoundTest is Test {
    MoonpotRound1 round;
    MockUSDC usdc;
    address manager = address(0xBEEF);
    address stranger = address(0xBAD);
    address recipient = address(0xC0FFEE);

    function setUp() public {
        usdc = new MockUSDC();
        round = new MoonpotRound1(manager, address(usdc));
    }

    /* --------------------------------- initial state --------------------------------- */

    function testInitialState() public view {
        assertEq(round.startTime(), type(uint256).max, "startTime should be max sentinel");
        assertEq(round.endTime(), 0);
        assertEq(round.tokensSold(), 0);
        assertEq(round.nftsMinted(), 0);
        assertEq(round.rewardPool(), 0);
        assertEq(round.scannedCount(), 0);
        assertEq(round.seedRequestId(), 0);
        assertEq(round.seed(), 0);
    }

    /* --------------------------------- start / end ----------------------------------- */

    function testStartSetsTimestamp() public {
        vm.warp(1_000_000);
        vm.prank(manager);
        round.start();
        assertEq(round.startTime(), 1_000_000);
    }

    function testEndSetsTimestamp() public {
        vm.warp(2_000_000);
        vm.prank(manager);
        round.end();
        assertEq(round.endTime(), 2_000_000);
    }

    function testStartOnlyManager() public {
        vm.expectRevert(AbstractMoonpotRound.Unauthorized.selector);
        vm.prank(stranger);
        round.start();
    }

    function testEndOnlyManager() public {
        vm.expectRevert(AbstractMoonpotRound.Unauthorized.selector);
        vm.prank(stranger);
        round.end();
    }

    /* --------------------------------- notify* counters ------------------------------ */

    function testNotifyPurchaseIncrements() public {
        vm.prank(manager);
        round.notifyPurchase(100);
        assertEq(round.tokensSold(), 100);

        vm.prank(manager);
        round.notifyPurchase(250);
        assertEq(round.tokensSold(), 350);
    }

    function testNotifyScannedIncrements() public {
        vm.prank(manager);
        round.notifyScanned(50);
        assertEq(round.scannedCount(), 50);

        vm.prank(manager);
        round.notifyScanned(150);
        assertEq(round.scannedCount(), 200);
    }

    function testNotifyNFTMintedIncrements() public {
        vm.prank(manager);
        round.notifyNFTMinted(3);
        assertEq(round.nftsMinted(), 3);

        vm.prank(manager);
        round.notifyNFTMinted(7);
        assertEq(round.nftsMinted(), 10);
    }

    function testNotifyPurchaseOnlyManager() public {
        vm.expectRevert(AbstractMoonpotRound.Unauthorized.selector);
        vm.prank(stranger);
        round.notifyPurchase(1);
    }

    function testNotifyScannedOnlyManager() public {
        vm.expectRevert(AbstractMoonpotRound.Unauthorized.selector);
        vm.prank(stranger);
        round.notifyScanned(1);
    }

    function testNotifyNFTMintedOnlyManager() public {
        vm.expectRevert(AbstractMoonpotRound.Unauthorized.selector);
        vm.prank(stranger);
        round.notifyNFTMinted(1);
    }

    /* --------------------------------- seed setters ---------------------------------- */

    function testSetSeedRequestId() public {
        vm.prank(manager);
        round.setSeedRequestId(42);
        assertEq(round.seedRequestId(), 42);
    }

    function testSetSeed() public {
        vm.prank(manager);
        round.setSeed(0xDEADBEEF);
        assertEq(round.seed(), 0xDEADBEEF);
    }

    function testSetSeedRequestIdOnlyManager() public {
        vm.expectRevert(AbstractMoonpotRound.Unauthorized.selector);
        vm.prank(stranger);
        round.setSeedRequestId(1);
    }

    function testSetSeedOnlyManager() public {
        vm.expectRevert(AbstractMoonpotRound.Unauthorized.selector);
        vm.prank(stranger);
        round.setSeed(1);
    }

    /* --------------------------------- deposit / release ----------------------------- */

    function testDepositFundsIncrementsPool() public {
        vm.prank(manager);
        round.depositFunds(1_000e6);
        assertEq(round.rewardPool(), 1_000e6);

        vm.prank(manager);
        round.depositFunds(500e6);
        assertEq(round.rewardPool(), 1_500e6);
    }

    function testDepositFundsOnlyManager() public {
        vm.expectRevert(AbstractMoonpotRound.Unauthorized.selector);
        vm.prank(stranger);
        round.depositFunds(1);
    }

    function testReleaseRewardTransfersAndDecrementsPool() public {
        // Seed the round with USDC and bookkeeping
        usdc.transfer(address(round), 1_000e6);
        vm.prank(manager);
        round.depositFunds(1_000e6);

        vm.prank(manager);
        round.releaseReward(recipient, 250e6);

        assertEq(usdc.balanceOf(recipient), 250e6);
        assertEq(usdc.balanceOf(address(round)), 750e6);
        assertEq(round.rewardPool(), 750e6);
    }

    function testReleaseRewardRevertsOnInsufficientFunds() public {
        // depositFunds tracks 100; rewardPool < amount triggers InsufficientFunds
        usdc.transfer(address(round), 100e6);
        vm.prank(manager);
        round.depositFunds(100e6);

        vm.prank(manager);
        vm.expectRevert(AbstractMoonpotRound.InsufficientFunds.selector);
        round.releaseReward(recipient, 101e6);
    }

    function testReleaseRewardOnlyManager() public {
        vm.expectRevert(AbstractMoonpotRound.Unauthorized.selector);
        vm.prank(stranger);
        round.releaseReward(recipient, 1);
    }

    /* --------------------------------- interface getters ----------------------------- */

    function testGetters() public {
        // setSeed first so seed-dependent getters return the set value
        vm.startPrank(manager);
        round.setSeed(0x1234);
        round.setSeedRequestId(7);
        vm.warp(123);
        round.start();
        vm.warp(456);
        round.end();
        round.notifyPurchase(10);
        round.notifyScanned(5);
        round.notifyNFTMinted(2);
        vm.stopPrank();

        assertEq(round.getRoundId(), 1);
        assertEq(round.getPricePerToken(), 1.15e6);
        assertEq(round.getCompanyShare(), 0.10e6);
        assertEq(round.getCommunityShare(), 1.00e6);
        assertEq(round.getLiquidityShare(), 0.05e6);
        assertEq(round.getTokenCount(), 1_000_000);
        assertEq(round.getTokensSold(), 10);
        assertEq(round.getNFTCount(), 99_991);
        assertEq(round.getNFTsMinted(), 2);
        assertEq(round.getStartTime(), 123);
        assertEq(round.getEndTime(), 456);
        assertEq(round.getScannedCount(), 5);
        assertEq(round.getSeedRequestId(), 7);
        assertEq(round.getSeed(), 0x1234);
    }
}
