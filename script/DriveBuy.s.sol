// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../contracts/MoonpotManager.sol";
import "../contracts/IMoonpotRound.sol";
import "../contracts/MoonpotNFT.sol";
import "../contracts/mocks/MockVRFCoordinator.sol";

/// @notice Drives one full purchase against a local-fork deployment:
/// fund buyer -> approve -> buyFor -> vrf.fulfill -> processBuy, then prints the result.
///
/// IMPORTANT (fork gotcha): the NFT recipient must be a CODELESS EOA on the
/// fork. Anvil's default account[0] (0xf39F…2266) is a live *contract* on Base
/// mainnet, so minting an NFT to it triggers onERC721Received and reverts. We
/// therefore derive a fresh throwaway buyer key here and fund it from the
/// deployer.
///
/// Reads the deployed addresses from env (printed by DeployLocal):
///   MANAGER, USDC, VRF, NFT   (addresses)
///   TOKENS                    (how many TMP to buy; default 100)
///   PRIVATE_KEY               (deployer/funder key; default Anvil account[0])
///
///   MANAGER=0x.. USDC=0x.. VRF=0x.. NFT=0x.. \
///   forge script script/DriveBuy.s.sol:DriveBuy \
///       --rpc-url http://127.0.0.1:8545 --broadcast --slow
contract DriveBuy is Script {
    function run() external {
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(
                0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
            )
        );
        // Throwaway buyer; its address is effectively random -> codeless on Base.
        uint256 buyerKey = vm.envOr(
            "BUYER_KEY",
            uint256(keccak256("moonpot.local.buyer.v1"))
        );
        address buyer = vm.addr(buyerKey);
        require(buyer.code.length == 0, "buyer must be a codeless EOA on the fork");

        MoonpotManager mp = MoonpotManager(vm.envAddress("MANAGER"));
        IERC20 usdc = IERC20(vm.envAddress("USDC"));
        DeployableVRFCoordinatorV2_5Mock vrf = DeployableVRFCoordinatorV2_5Mock(
            vm.envAddress("VRF")
        );
        MoonpotNFT nft = MoonpotNFT(vm.envAddress("NFT"));
        uint256 numTokens = vm.envOr("TOKENS", uint256(100));

        IMoonpotRound round = mp.rounds(mp._currentRoundId());
        uint256 amount = round.getPricePerToken() * numTokens;

        // 1. Fund the buyer with USDC + a little ETH for gas (from the deployer).
        vm.startBroadcast(deployerKey);
        usdc.transfer(buyer, amount);
        (bool ok, ) = payable(buyer).call{value: 0.05 ether}("");
        require(ok, "buyer ETH funding failed");
        vm.stopBroadcast();

        // 2. Buyer approves the manager (so buyFor's permit branch is skipped).
        vm.startBroadcast(buyerKey);
        usdc.approve(address(mp), amount);
        vm.stopBroadcast();

        // 3. Deployer drives the buy, simulates the VRF callback, mints NFTs.
        vm.startBroadcast(deployerKey);
        mp.buyFor(buyer, amount, 0, 0, bytes32(0), bytes32(0));
        uint256 purchaseId = mp.lastPurchaseId();
        uint256 reqId = vrf.latestRequestId();
        vrf.fulfill(reqId);
        mp.processBuy(purchaseId);
        vm.stopBroadcast();

        console.log("=== buy driven ===");
        console.log("buyer          %s", buyer);
        console.log("tokens bought  %s", numTokens);
        console.log("purchaseId     %s", purchaseId);
        console.log("vrf reqId      %s", reqId);
        console.log("NFTs minted    %s", nft.balanceOf(buyer));
        console.log("TMP balance    %s", IERC20(address(mp.tmp())).balanceOf(buyer));
    }
}
