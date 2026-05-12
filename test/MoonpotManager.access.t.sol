// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/MoonpotManager.sol";
import "../contracts/MoonpotToken.sol";
import "../contracts/MoonpotNFT.sol";
import "../contracts/MoonpotRound1.sol";
import "../contracts/mocks/MockUSDC.sol";

/// @notice Access-control + admin-method tests for MoonpotManager.
/// Constructs the manager with stub addresses for the heavy deps (VRF /
/// PoolManager / PositionManager / Permit2 / hook); no method exercised here
/// reaches those deps.
contract MoonpotManagerAccessTest is Test {
    MoonpotManager manager;
    MoonpotToken tmp;
    MoonpotNFT nft;
    MockUSDC usdc;
    MoonpotRound1 round1;

    address owner = address(this); // deployer = owner per VRFConsumerBaseV2Plus
    address company = address(0xC0C0);
    address newCompany = address(0xCAFE);
    address stranger = address(0xBAD);

    // Stub addresses; non-zero so constructor passes, never actually called
    address vrf = address(0x1111);
    address poolm = address(0x2222);
    address posm = address(0x3333);
    address permit2 = address(0x4444);
    address hook = address(0x5555);
    bytes32 vrfKey = bytes32(uint256(0xAA));
    uint256 vrfSub = 999;

    function setUp() public {
        usdc = new MockUSDC();
        tmp = new MoonpotToken();
        nft = new MoonpotNFT();

        manager = new MoonpotManager(
            address(usdc),
            address(tmp),
            address(nft),
            company,
            vrf,
            vrfKey,
            vrfSub,
            poolm,
            posm,
            permit2,
            hook
        );

        round1 = new MoonpotRound1(address(manager), address(usdc));
    }

    /* --------------------------------- constructor reverts --------------------------- */

    function testConstructorRevertsOnAnyZeroAddress() public {
        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        new MoonpotManager(address(0), address(tmp), address(nft), company, vrf, vrfKey, vrfSub, poolm, posm, permit2, hook);

        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        new MoonpotManager(address(usdc), address(0), address(nft), company, vrf, vrfKey, vrfSub, poolm, posm, permit2, hook);

        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        new MoonpotManager(address(usdc), address(tmp), address(0), company, vrf, vrfKey, vrfSub, poolm, posm, permit2, hook);

        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        new MoonpotManager(address(usdc), address(tmp), address(nft), address(0), vrf, vrfKey, vrfSub, poolm, posm, permit2, hook);

        // _vrf is also checked separately by VRFConsumerBaseV2Plus, so revert reason may differ
        vm.expectRevert();
        new MoonpotManager(address(usdc), address(tmp), address(nft), company, address(0), vrfKey, vrfSub, poolm, posm, permit2, hook);

        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        new MoonpotManager(address(usdc), address(tmp), address(nft), company, vrf, vrfKey, vrfSub, address(0), posm, permit2, hook);

        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        new MoonpotManager(address(usdc), address(tmp), address(nft), company, vrf, vrfKey, vrfSub, poolm, address(0), permit2, hook);

        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        new MoonpotManager(address(usdc), address(tmp), address(nft), company, vrf, vrfKey, vrfSub, poolm, posm, address(0), hook);

        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        new MoonpotManager(address(usdc), address(tmp), address(nft), company, vrf, vrfKey, vrfSub, poolm, posm, permit2, address(0));
    }

    function testConstructorSetsImmutables() public view {
        assertEq(address(manager.usdc()), address(usdc));
        assertEq(address(manager.tmp()), address(tmp));
        assertEq(address(manager.nft()), address(nft));
        assertEq(manager.company(), company);
        assertEq(address(manager.poolManager()), poolm);
        assertEq(address(manager.positionManager()), posm);
        assertEq(address(manager.permit2()), permit2);
        assertEq(manager.hook(), hook);
        assertEq(manager.vrfKeyHash(), vrfKey);
        assertEq(manager.vrfSubId(), vrfSub);
        assertEq(manager.MAX_ROUNDS(), 28);
        assertEq(manager.MAX_PURCHASE_LIMIT(), 10_000);
        assertEq(manager.VRF_TIMEOUT(), 24 hours);
        assertEq(manager.INIT_TICK_PREMIUM(), 1_200);
        assertFalse(manager.isInitialized());
    }

    /* --------------------------------- setRound -------------------------------------- */

    function testSetRoundHappy() public {
        vm.expectEmit(true, false, false, true, address(manager));
        emit MoonpotManager.RoundSet(1, address(round1));
        manager.setRound(1, address(round1));

        assertEq(address(manager.rounds(1)), address(round1));
    }

    function testSetRoundRevertsOnZeroId() public {
        vm.expectRevert(MoonpotManager.RoundOutOfBounds.selector);
        manager.setRound(0, address(round1));
    }

    function testSetRoundRevertsOnOverMax() public {
        vm.expectRevert(MoonpotManager.RoundOutOfBounds.selector);
        manager.setRound(29, address(round1)); // MAX_ROUNDS + 1
    }

    function testSetRoundRevertsWhenAlreadySet() public {
        manager.setRound(1, address(round1));
        MoonpotRound1 round1Other = new MoonpotRound1(address(manager), address(usdc));
        vm.expectRevert(MoonpotManager.RoundExists.selector);
        manager.setRound(1, address(round1Other));
    }

    function testSetRoundRevertsOnZeroAddr() public {
        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        manager.setRound(1, address(0));
    }

    function testSetRoundOnlyOwner() public {
        vm.expectRevert(); // Chainlink "Only callable by owner"
        vm.prank(stranger);
        manager.setRound(1, address(round1));
    }

    /* --------------------------------- setCompany ------------------------------------ */

    function testSetCompanyHappy() public {
        vm.expectEmit(false, false, false, true, address(manager));
        emit MoonpotManager.CompanySet(newCompany);
        manager.setCompany(newCompany);
        assertEq(manager.company(), newCompany);
    }

    function testSetCompanyRevertsOnZero() public {
        vm.expectRevert(MoonpotManager.InvalidAddress.selector);
        manager.setCompany(address(0));
    }

    function testSetCompanyOnlyOwner() public {
        vm.expectRevert();
        vm.prank(stranger);
        manager.setCompany(newCompany);
    }

    /* --------------------------------- setVRFParams ---------------------------------- */

    function testSetVRFParams() public {
        bytes32 newKey = bytes32(uint256(0xBB));
        uint256 newSub = 1234;
        uint32 newGas = 500_000;

        vm.expectEmit(false, false, false, true, address(manager));
        emit MoonpotManager.VRFParamsSet(newKey, newSub, newGas);
        manager.setVRFParams(newKey, newSub, newGas);

        assertEq(manager.vrfKeyHash(), newKey);
        assertEq(manager.vrfSubId(), newSub);
        assertEq(manager.vrfCallbackGasLimit(), newGas);
    }

    function testSetVRFParamsOnlyOwner() public {
        vm.expectRevert();
        vm.prank(stranger);
        manager.setVRFParams(bytes32(0), 1, 100_000);
    }

    /* --------------------------------- retryRoundReveal ------------------------------ */

    function testRetryRoundRevealRevertsOnMissingRound() public {
        vm.expectRevert(MoonpotManager.RoundMissing.selector);
        manager.retryRoundReveal(1);
    }

    function testRetryRoundRevealRevertsWhenNotEnded() public {
        manager.setRound(1, address(round1));
        // round1 was just constructed; endTime == 0
        vm.expectRevert(MoonpotManager.RoundNotEnded.selector);
        manager.retryRoundReveal(1);
    }

    function testRetryRoundRevealRevertsWhenAlreadySeeded() public {
        manager.setRound(1, address(round1));

        // Manipulate round state as the manager (msg.sender = manager contract)
        vm.startPrank(address(manager));
        round1.end();
        round1.setSeed(0xABC);
        vm.stopPrank();

        vm.expectRevert(MoonpotManager.AlreadyFilled.selector);
        manager.retryRoundReveal(1);
    }

    function testRetryRoundRevealOnlyOwner() public {
        manager.setRound(1, address(round1));
        vm.expectRevert();
        vm.prank(stranger);
        manager.retryRoundReveal(1);
    }
}
