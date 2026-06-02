// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import "../contracts/MoonpotHook.sol";
import "../contracts/MoonpotManager.sol";
import "../contracts/MoonpotToken.sol";
import "../contracts/MoonpotNFT.sol";
import "../contracts/MoonpotRound1.sol";
import "../contracts/MoonpotRound2.sol";
import "../contracts/MoonpotRound3.sol";
import "../contracts/MoonpotRound4.sol";
import "../contracts/MoonpotRound5.sol";
import "../contracts/mocks/MockUSDC.sol";
import "../contracts/mocks/MockVRFCoordinator.sol";

/// @notice Deploys the full Moonpot system onto a LOCAL fork of Base mainnet.
///
/// Why a fork: the system depends on the live Uniswap v4 PoolManager,
/// PositionManager and Permit2, which only exist on Base. A fork gives us a
/// local copy of that state so `init` can create the real pool and the hook's
/// swap / injection paths actually run — without deploying to mainnet.
///
/// Two pieces are mocked, on purpose:
///   - USDC  -> MockUSDC (deployer is minted 10B, so no whale/storage tricks)
///   - VRF   -> DeployableVRFCoordinatorV2_5Mock (Chainlink has no off-chain
///              node on a local fork; call `vrf.fulfill(reqId)` to simulate it)
/// Everything else (v4, Permit2) is the real Base code via the fork.
///
/// Usage (see script/local-fork.sh for the one-command wrapper):
///   anvil --fork-url $BASE_RPC_URL
///   forge script script/DeployLocal.s.sol:DeployLocal \
///       --rpc-url http://127.0.0.1:8545 --broadcast
contract DeployLocal is Script {
    // Canonical Base mainnet addresses (present on the fork).
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // forge-script CREATE2 proxy: `new X{salt:..}` routes through this, so the
    // hook salt must be mined against it (not address(this)).
    address constant CREATE2_DEPLOYER =
        0x4e59b44847b379578588920cA78FbF26c0B4956C;

    uint160 constant HOOK_FLAGS =
        Hooks.BEFORE_INITIALIZE_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

    // Local-only VRF identifiers (mock ignores them).
    bytes32 constant VRF_KEY = bytes32(uint256(0xAA));
    uint256 constant VRF_SUB = 1;

    function run() external {
        // --- Config (all env-overridable) ---
        // Default key = Anvil's account[0] (publicly known; LOCAL ONLY).
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(
                0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
            )
        );
        address deployer = vm.addr(deployerKey);
        uint256 initialUsdc = vm.envOr("INITIAL_USDC", uint256(100_000e6));
        int24 ceilingTick = int24(vm.envOr("CEILING_TICK", int256(-245_880)));
        address company = vm.envOr("COMPANY", address(0xC0C0));
        // Optional second-account buyer to pre-fund; defaults to none.
        address buyer = vm.envOr("BUYER", address(0));
        uint256 buyerFund = vm.envOr("BUYER_FUND_USDC", uint256(10_000e6));

        vm.startBroadcast(deployerKey);

        // 1. Tokens / NFT / VRF mock (deployer receives 10B MockUSDC here).
        MockUSDC usdc = new MockUSDC();
        MoonpotToken tmp = new MoonpotToken();
        MoonpotNFT nft = new MoonpotNFT();
        DeployableVRFCoordinatorV2_5Mock vrf = new DeployableVRFCoordinatorV2_5Mock();

        // 2. Mine + CREATE2-deploy the hook so its address carries the v4 flags.
        bytes memory args = abi.encode(
            IPoolManager(POOL_MANAGER),
            POSITION_MANAGER,
            PERMIT2,
            address(usdc),
            address(tmp),
            deployer
        );
        (address hookAddr, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            HOOK_FLAGS,
            type(MoonpotHook).creationCode,
            args
        );
        MoonpotHook hook = new MoonpotHook{salt: salt}(
            IPoolManager(POOL_MANAGER),
            POSITION_MANAGER,
            PERMIT2,
            address(usdc),
            address(tmp),
            deployer
        );
        require(address(hook) == hookAddr, "hook address mismatch");

        // 3. Manager + rounds.
        MoonpotManager mp = new MoonpotManager(
            address(usdc),
            address(tmp),
            address(nft),
            company,
            address(vrf),
            VRF_KEY,
            VRF_SUB,
            POOL_MANAGER,
            POSITION_MANAGER,
            PERMIT2,
            address(hook)
        );

        MoonpotRound1 round1 = new MoonpotRound1(address(mp), address(usdc));
        MoonpotRound2 round2 = new MoonpotRound2(address(mp), address(usdc));
        MoonpotRound3 round3 = new MoonpotRound3(address(mp), address(usdc));
        MoonpotRound4 round4 = new MoonpotRound4(address(mp), address(usdc));
        MoonpotRound5 round5 = new MoonpotRound5(address(mp), address(usdc));

        // 4. Wire managers + rounds.
        tmp.setManager(address(mp));
        nft.setManager(address(mp));
        hook.setManager(address(mp));
        nft.setBaseURI("https://api.themoonpot.com/nft/");
        mp.setRound(1, address(round1));
        mp.setRound(2, address(round2));
        mp.setRound(3, address(round3));
        mp.setRound(4, address(round4));
        mp.setRound(5, address(round5));

        // 5. Fund the manager, create the pool, open round 1.
        usdc.transfer(address(mp), initialUsdc);
        mp.init(initialUsdc, ceilingTick);
        mp.start();

        // 6. Optional: pre-fund a buyer account for convenience.
        if (buyer != address(0) && buyerFund > 0) {
            usdc.transfer(buyer, buyerFund);
        }

        vm.stopBroadcast();

        // 7. Report (copy these into env vars to drive buys; see README).
        console.log("=== Moonpot local-fork deployment ===");
        console.log("deployer       %s", deployer);
        console.log("USDC  (mock)   %s", address(usdc));
        console.log("TMP            %s", address(tmp));
        console.log("NFT            %s", address(nft));
        console.log("VRF   (mock)   %s", address(vrf));
        console.log("HOOK           %s", address(hook));
        console.log("MANAGER        %s", address(mp));
        console.log("ROUND1         %s", address(round1));
        console.log("ROUND2         %s", address(round2));
        console.log("ROUND3         %s", address(round3));
        console.log("ROUND4         %s", address(round4));
        console.log("ROUND5         %s", address(round5));
        if (buyer != address(0)) {
            console.log("buyer funded   %s (%s USDC base units)", buyer, buyerFund);
        }
    }
}
