// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "../contracts/MoonpotToken.sol";

contract MoonpotTokenTest is Test {
    MoonpotToken token;
    address owner = address(this);
    address manager = address(0xBEEF);
    address alice = address(0xAAA);

    function setUp() public {
        token = new MoonpotToken();
    }

    function testConstructorSetsNameAndSymbol() public view {
        assertEq(token.name(), "The Moonpot Token");
        assertEq(token.symbol(), "TMP");
        assertEq(token.totalSupply(), 0);
    }

    function testSetManagerOnlyOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        vm.prank(alice);
        token.setManager(manager);
        vm.expectRevert(MoonpotToken.InvalidAddress.selector);
        token.setManager(address(0));

        vm.expectEmit(true, false, false, true);
        emit MoonpotToken.ManagerSet(manager);
        token.setManager(manager);

        assertEq(token.manager(), manager);
    }

    function testMintOnlySale() public {
        token.setManager(manager);

        vm.expectRevert(MoonpotToken.Unauthorized.selector);
        token.mint(alice, 100);

        vm.prank(manager);
        vm.expectEmit(true, true, true, true);
        emit MoonpotToken.Minted(alice, 100);
        token.mint(alice, 100);

        assertEq(token.totalSupply(), 100);
        assertEq(token.balanceOf(alice), 100);
    }
}
