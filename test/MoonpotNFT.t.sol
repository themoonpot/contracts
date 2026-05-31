// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/Test.sol";
import "../contracts/MoonpotNFT.sol";

contract MoonpotNFTTest is Test {
    MoonpotNFT nft;

    address deployer = address(this);
    address alice = address(0x2);
    address bob = address(0x3);

    function setUp() public {
        nft = new MoonpotNFT();
        nft.setManager(address(this));
    }

    function testConstructorValues() public view {
        assertEq(nft.totalMinted(), 0);
        assertEq(nft.manager(), deployer);
        assertEq(nft.owner(), deployer);
    }

    function testOnlyManagerCanMint() public {
        vm.expectRevert(MoonpotNFT.Unauthorized.selector);
        vm.prank(alice);
        nft.mintTo(bob, 10, 1);

        nft.mintTo(alice, 10, 1);

        assertEq(nft.totalMinted(), 10);
        assertEq(nft.ownerOf(5), alice);
    }

    function testOwnerCanSetBaseURIAndIncrementsVersion() public {
        uint256 beforeVersion = nft.metadataVersion();
        nft.setBaseURI("https://moonpot.example/");
        uint256 afterVersion = nft.metadataVersion();

        assertEq(afterVersion, beforeVersion + 1);

        nft.mintTo(alice, 1, 1);
        string memory uri = nft.tokenURI(0);

        assertTrue(bytes(uri).length > 0);
    }

    function testEmitsBatchMetadataUpdate() public {
        nft.mintTo(alice, 1, 1);

        vm.expectEmit(true, true, true, true, address(nft));
        emit MoonpotNFT.BatchMetadataUpdate(0, 0);
        nft.setBaseURI("https://moonpot.new/");
    }

    function testCannotSetBaseURIAfterFreeze() public {
        nft.freezeBaseURI();
        vm.expectRevert(MoonpotNFT.BaseURIFrozen.selector);
        nft.setBaseURI("https://blocked.example/");
    }

    function testNonOwnerCannotSetBaseURIOrFreeze() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        vm.prank(alice);
        nft.setBaseURI("https://hack.example/");

        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        vm.prank(alice);
        nft.freezeBaseURI();
    }

    function testFreezePreventsFutureUpdates() public {
        nft.setBaseURI("https://initial.example/");
        nft.freezeBaseURI();

        vm.expectRevert(MoonpotNFT.BaseURIFrozen.selector);
        nft.setBaseURI("https://new.example/");
    }

    function testFreezeBaseURIEmitsEvent() public {
        vm.expectEmit(false, false, false, true, address(nft));
        emit MoonpotNFT.BaseURILocked();
        nft.freezeBaseURI();
    }

    function testMetadataVersionDoesNotChangeOnFreeze() public {
        uint256 beforeVersion = nft.metadataVersion();
        nft.freezeBaseURI();
        uint256 afterVersion = nft.metadataVersion();

        assertEq(afterVersion, beforeVersion);
    }

    /* ------------------ F-2026-17212: roundId survives transfers --------------------- */

    function testRoundIdPersistsAfterTransfer() public {
        nft.mintTo(alice, 1, 1);
        assertEq(nft.getRound(0), 1);

        vm.prank(alice);
        nft.transferFrom(alice, bob, 0);

        assertEq(nft.ownerOf(0), bob);
        assertEq(nft.getRound(0), 1);
    }

    function testRoundIdPersistsAfterTransfer_BatchMint() public {
        nft.mintTo(alice, 3, 1);

        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);

        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.getRound(0), 1);
        assertEq(nft.getRound(1), 1);
        assertEq(nft.getRound(2), 1);
    }
}
