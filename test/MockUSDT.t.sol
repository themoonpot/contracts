// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/mocks/MockUSDT.sol";

contract MockUSDTTest is Test {
    MockUSDT usdt;
    address deployer = address(this);
    address alice = address(0x1);
    address bob = address(0x2);

    function setUp() public {
        usdt = new MockUSDT();
    }

    function testInitialSupplyMintedToDeployer() public view {
        assertEq(usdt.totalSupply(), 5_000_000_000e6);
        assertEq(usdt.balanceOf(deployer), 5_000_000_000e6);
    }

    function testDecimalsIsSix() public view {
        assertEq(usdt.decimals(), 6);
    }

    function testTransferSuccess() public {
        usdt.transfer(alice, 100e6);

        assertEq(usdt.balanceOf(alice), 100e6);
        assertEq(usdt.balanceOf(deployer), 5_000_000_000e6 - 100e6);
    }

    function testTransferInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert();

        usdt.transfer(bob, 1e6);
    }

    function testApproveAndTransferFrom() public {
        usdt.approve(alice, 50e6);
        vm.prank(alice);

        usdt.transferFrom(deployer, bob, 50e6);

        assertEq(usdt.balanceOf(bob), 50e6);
        assertEq(usdt.allowance(deployer, alice), 0);
    }

    function testTransferFromWithoutApprovalFails() public {
        vm.prank(alice);
        vm.expectRevert();

        usdt.transferFrom(deployer, bob, 1e6);
    }
}
