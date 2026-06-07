// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
import "../contracts/mocks/MockToken.sol";
import "../contracts/mocks/MockNFT.sol";
import "../contracts/mocks/MockManager.sol";
import "../contracts/mocks/MockHook.sol";
import "../contracts/mocks/MockRound1.sol";
import "../contracts/mocks/MockRound2.sol";
import "../contracts/mocks/MockRound3.sol";
import "../contracts/mocks/MockRound4.sol";
import "../contracts/mocks/MockRound5.sol";

/// @notice One-shot deploy of the full Moonpot system to Base mainnet.
///
/// `MOCK=true`  -> deploys MockUSDC + the de-branded Mock* contracts (a safe,
///                clearly-distinct copy for end-to-end testing).
/// `MOCK=false` -> deploys the real Moonpot* contracts against live Circle USDC
///                (the deployer must already hold INITIAL_USDC of real USDC).
///
/// Both use real Chainlink VRF. The hook salt is mined in-script (HookMiner), so
/// there is no offline mining / config editing / params files — just one command.
///
/// Usage:
///   # mock
///   MOCK=true forge script scripts/DeployBase.s.sol:DeployBase \
///       --rpc-url "$BASE_RPC_URL" --account moonpot-deployer --broadcast --verify
///   # production
///   forge script scripts/DeployBase.s.sol:DeployBase \
///       --rpc-url "$BASE_RPC_URL" --account moonpot-deployer --broadcast --verify
///
/// Tunable via env: INITIAL_USDC, CEILING_TICK, COMPANY, VRF_COORDINATOR,
/// VRF_KEY_HASH, VRF_SUB_ID (or PRIVATE_KEY instead of --account).
contract DeployBase is Script {
    // Canonical Base mainnet addresses.
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Default real Chainlink VRF v2.5 config on Base (override via env).
    address constant VRF_COORDINATOR_DEFAULT =
        0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634;
    bytes32 constant VRF_KEY_HASH_DEFAULT =
        0x00b81b5a830cb0a4009fbd8904de511e28631e62ce5ad231373d3cdad373ccab;

    // forge-script CREATE2 proxy: `new X{salt:..}` routes through this, so the
    // hook salt must be mined against it.
    address constant CREATE2_DEPLOYER =
        0x4e59b44847b379578588920cA78FbF26c0B4956C;

    uint160 constant HOOK_FLAGS =
        Hooks.BEFORE_INITIALIZE_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

    function run() external {
        bool mock = vm.envOr("MOCK", false);
        uint256 initialUsdc = vm.envOr("INITIAL_USDC", uint256(1_000e6));
        int24 ceilingTick = int24(vm.envOr("CEILING_TICK", int256(-245_880)));
        address vrfCoordinator = vm.envOr(
            "VRF_COORDINATOR",
            VRF_COORDINATOR_DEFAULT
        );
        bytes32 vrfKeyHash = vm.envOr("VRF_KEY_HASH", VRF_KEY_HASH_DEFAULT);
        uint256 vrfSubId = vm.envOr("VRF_SUB_ID", uint256(0));
        require(vrfSubId != 0, "set VRF_SUB_ID");

        // Signer: PRIVATE_KEY env if given, else the CLI --account / --sender.
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer;
        if (pk != 0) {
            deployer = vm.addr(pk);
            vm.startBroadcast(pk);
        } else {
            deployer = msg.sender;
            vm.startBroadcast();
        }
        address company = vm.envOr("COMPANY", deployer);

        // 1. Payment token: MockUSDC (mints 10B to deployer) or live USDC.
        address usdc = mock ? address(new MockUSDC()) : USDC_BASE;

        // 2. Token + NFT (Mock* inherit the real logic, distinct name).
        MoonpotToken tmp;
        MoonpotNFT nft;
        if (mock) {
            tmp = new MockToken();
            nft = new MockNFT();
        } else {
            tmp = new MoonpotToken();
            nft = new MoonpotNFT();
        }

        // 3. Mine + CREATE2-deploy the hook so its address carries the v4 flags.
        bytes memory args = abi.encode(
            IPoolManager(POOL_MANAGER),
            POSITION_MANAGER,
            PERMIT2,
            usdc,
            address(tmp),
            deployer
        );
        address hookAddr;
        bytes32 salt;
        MoonpotHook hook;
        if (mock) {
            (hookAddr, salt) = HookMiner.find(
                CREATE2_DEPLOYER,
                HOOK_FLAGS,
                type(MockHook).creationCode,
                args
            );
            hook = new MockHook{salt: salt}(
                IPoolManager(POOL_MANAGER),
                POSITION_MANAGER,
                PERMIT2,
                usdc,
                address(tmp),
                deployer
            );
        } else {
            (hookAddr, salt) = HookMiner.find(
                CREATE2_DEPLOYER,
                HOOK_FLAGS,
                type(MoonpotHook).creationCode,
                args
            );
            hook = new MoonpotHook{salt: salt}(
                IPoolManager(POOL_MANAGER),
                POSITION_MANAGER,
                PERMIT2,
                usdc,
                address(tmp),
                deployer
            );
        }
        require(address(hook) == hookAddr, "hook address mismatch");

        // 4. Manager.
        MoonpotManager mp;
        if (mock) {
            mp = new MockManager(
                usdc,
                address(tmp),
                address(nft),
                company,
                vrfCoordinator,
                vrfKeyHash,
                vrfSubId,
                POOL_MANAGER,
                POSITION_MANAGER,
                PERMIT2,
                address(hook)
            );
        } else {
            mp = new MoonpotManager(
                usdc,
                address(tmp),
                address(nft),
                company,
                vrfCoordinator,
                vrfKeyHash,
                vrfSubId,
                POOL_MANAGER,
                POSITION_MANAGER,
                PERMIT2,
                address(hook)
            );
        }

        // 5. Rounds.
        address r1 = mock
            ? address(new MockRound1(address(mp), usdc))
            : address(new MoonpotRound1(address(mp), usdc));
        address r2 = mock
            ? address(new MockRound2(address(mp), usdc))
            : address(new MoonpotRound2(address(mp), usdc));
        address r3 = mock
            ? address(new MockRound3(address(mp), usdc))
            : address(new MoonpotRound3(address(mp), usdc));
        address r4 = mock
            ? address(new MockRound4(address(mp), usdc))
            : address(new MoonpotRound4(address(mp), usdc));
        address r5 = mock
            ? address(new MockRound5(address(mp), usdc))
            : address(new MoonpotRound5(address(mp), usdc));

        // 6. Wire managers + rounds.
        tmp.setManager(address(mp));
        nft.setManager(address(mp));
        hook.setManager(address(mp));
        nft.setBaseURI("https://api.themoonpot.com/nft/");
        mp.setRound(1, r1);
        mp.setRound(2, r2);
        mp.setRound(3, r3);
        mp.setRound(4, r4);
        mp.setRound(5, r5);

        // 7. Seed the manager, create the pool, open round 1.
        IERC20(usdc).transfer(address(mp), initialUsdc);
        mp.init(initialUsdc, ceilingTick);
        mp.start();

        vm.stopBroadcast();

        // 8. Report.
        console.log(mock ? "=== MOCK deploy ===" : "=== PRODUCTION deploy ===");
        console.log("deployer        %s", deployer);
        // If usdcIsToken0 is true, the default CEILING_TICK sign is likely wrong
        // — recompute it (scripts/calculate-ceiling-tick.ts) and re-run.
        console.log("usdcIsToken0    %s", uint160(usdc) < uint160(address(tmp)));
        console.log("USDC            %s", usdc);
        console.log("TMP             %s", address(tmp));
        console.log("NFT             %s", address(nft));
        console.log("HOOK            %s", address(hook));
        console.log("MANAGER         %s", address(mp));
        console.log("ROUND1          %s", r1);
        console.log("ROUND2          %s", r2);
        console.log("ROUND3          %s", r3);
        console.log("ROUND4          %s", r4);
        console.log("ROUND5          %s", r5);
    }
}
