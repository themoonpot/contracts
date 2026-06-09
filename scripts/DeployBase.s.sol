// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMoonpotRound} from "../contracts/IMoonpotRound.sol";

import "../contracts/MoonpotHook.sol";
import "../contracts/MoonpotManager.sol";
import "../contracts/MoonpotToken.sol";
import "../contracts/MoonpotNFT.sol";
import "../contracts/MoonpotRound1.sol";
import "../contracts/MoonpotRound2.sol";
import "../contracts/MoonpotRound3.sol";
import "../contracts/MoonpotRound4.sol";
import "../contracts/MoonpotRound5.sol";
import "../contracts/MoonpotRound6.sol";
import "../contracts/MoonpotRound7.sol";
import "../contracts/MoonpotRound8.sol";
import "../contracts/MoonpotRound9.sol";
import "../contracts/MoonpotRound10.sol";
import "../contracts/MoonpotRound11.sol";
import "../contracts/MoonpotRound12.sol";
import "../contracts/MoonpotRound13.sol";
import "../contracts/MoonpotRound14.sol";
import "../contracts/MoonpotRound15.sol";
import "../contracts/MoonpotRound16.sol";
import "../contracts/MoonpotRound17.sol";
import "../contracts/MoonpotRound18.sol";
import "../contracts/MoonpotRound19.sol";
import "../contracts/MoonpotRound20.sol";
import "../contracts/MoonpotRound21.sol";
import "../contracts/MoonpotRound22.sol";
import "../contracts/MoonpotRound23.sol";
import "../contracts/MoonpotRound24.sol";
import "../contracts/MoonpotRound25.sol";
import "../contracts/MoonpotRound26.sol";
import "../contracts/MoonpotRound27.sol";
import "../contracts/MoonpotRound28.sol";
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
import "../contracts/mocks/MockRound6.sol";
import "../contracts/mocks/MockRound7.sol";
import "../contracts/mocks/MockRound8.sol";
import "../contracts/mocks/MockRound9.sol";
import "../contracts/mocks/MockRound10.sol";
import "../contracts/mocks/MockRound11.sol";
import "../contracts/mocks/MockRound12.sol";
import "../contracts/mocks/MockRound13.sol";
import "../contracts/mocks/MockRound14.sol";
import "../contracts/mocks/MockRound15.sol";
import "../contracts/mocks/MockRound16.sol";
import "../contracts/mocks/MockRound17.sol";
import "../contracts/mocks/MockRound18.sol";
import "../contracts/mocks/MockRound19.sol";
import "../contracts/mocks/MockRound20.sol";
import "../contracts/mocks/MockRound21.sol";
import "../contracts/mocks/MockRound22.sol";
import "../contracts/mocks/MockRound23.sol";
import "../contracts/mocks/MockRound24.sol";
import "../contracts/mocks/MockRound25.sol";
import "../contracts/mocks/MockRound26.sol";
import "../contracts/mocks/MockRound27.sol";
import "../contracts/mocks/MockRound28.sol";

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
    using PoolIdLibrary for PoolKey;

    // Canonical Base mainnet addresses.
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant POSITION_MANAGER =
        0x7C5f5A4bBd8fD63184577525326123B519429bDc;
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

    int24 constant TICK_SPACING = 60;
    // LP ceiling = final-round price x this multiple.
    uint256 constant CEILING_MULTIPLIER = 10;

    /// @dev Price (USDC, 6dp) -> tick, sign-aware.
    function _priceToTick(
        uint256 priceUSDC,
        bool usdcIsToken0
    ) internal pure returns (int24 tick) {
        uint256 ratio = FullMath.mulDiv(priceUSDC, 1 << 192, 1e18);
        uint160 sqrtPriceX96 = uint160(Math.sqrt(ratio));
        int24 tickRaw = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        tick = usdcIsToken0 ? -tickRaw : tickRaw;
        int24 r = tick % TICK_SPACING;
        tick = r < 0 ? tick - (TICK_SPACING + r) : tick - r;
    }

    function run() external {
        bool mock = vm.envOr("MOCK", false);
        uint256 initialUsdc = vm.envOr("INITIAL_USDC", uint256(1_000e6));
        address vrfCoordinator = vm.envOr(
            "VRF_COORDINATOR",
            VRF_COORDINATOR_DEFAULT
        );
        bytes32 vrfKeyHash = vm.envOr("VRF_KEY_HASH", VRF_KEY_HASH_DEFAULT);
        uint256 vrfSubId = vm.envOr("VRF_SUB_ID", uint256(0));
        require(vrfSubId != 0, "set VRF_SUB_ID");

        // Signer: PRIVATE_KEY env if given, else the CLI --account / --sender.
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        if (pk != 0) {
            vm.startBroadcast(pk);
        } else {
            vm.startBroadcast();
        }
        // The ACTUAL broadcast sender. With `--account` (and no `--sender`),
        // msg.sender here is Foundry's default sender, not the wallet — using it
        // would mis-own the hook and break the wiring. readCallers() returns the
        // real sender for every signer path.
        (, address deployer, ) = vm.readCallers();
        // Safe (multisig) to own everything post-deploy. If set, the deployer
        // EOA wires the whole system, then hands all ownership to the Safe.
        address safe = vm.envOr("SAFE", address(0));

        address company = vm.envOr(
            "COMPANY",
            safe == address(0) ? deployer : safe
        );

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

        // Token ordering — drives the ceiling-tick sign (computed before init).
        bool usdcIsToken0 = uint160(usdc) < uint160(address(tmp));

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

        // 5. Rounds (1..28). Each round is its own contract (distinct prize
        // table), so they're deployed explicitly; setRound is looped below.
        address[28] memory r;
        r[0] = mock
            ? address(new MockRound1(address(mp), usdc))
            : address(new MoonpotRound1(address(mp), usdc));
        r[1] = mock
            ? address(new MockRound2(address(mp), usdc))
            : address(new MoonpotRound2(address(mp), usdc));
        r[2] = mock
            ? address(new MockRound3(address(mp), usdc))
            : address(new MoonpotRound3(address(mp), usdc));
        r[3] = mock
            ? address(new MockRound4(address(mp), usdc))
            : address(new MoonpotRound4(address(mp), usdc));
        r[4] = mock
            ? address(new MockRound5(address(mp), usdc))
            : address(new MoonpotRound5(address(mp), usdc));
        r[5] = mock
            ? address(new MockRound6(address(mp), usdc))
            : address(new MoonpotRound6(address(mp), usdc));
        r[6] = mock
            ? address(new MockRound7(address(mp), usdc))
            : address(new MoonpotRound7(address(mp), usdc));
        r[7] = mock
            ? address(new MockRound8(address(mp), usdc))
            : address(new MoonpotRound8(address(mp), usdc));
        r[8] = mock
            ? address(new MockRound9(address(mp), usdc))
            : address(new MoonpotRound9(address(mp), usdc));
        r[9] = mock
            ? address(new MockRound10(address(mp), usdc))
            : address(new MoonpotRound10(address(mp), usdc));
        r[10] = mock
            ? address(new MockRound11(address(mp), usdc))
            : address(new MoonpotRound11(address(mp), usdc));
        r[11] = mock
            ? address(new MockRound12(address(mp), usdc))
            : address(new MoonpotRound12(address(mp), usdc));
        r[12] = mock
            ? address(new MockRound13(address(mp), usdc))
            : address(new MoonpotRound13(address(mp), usdc));
        r[13] = mock
            ? address(new MockRound14(address(mp), usdc))
            : address(new MoonpotRound14(address(mp), usdc));
        r[14] = mock
            ? address(new MockRound15(address(mp), usdc))
            : address(new MoonpotRound15(address(mp), usdc));
        r[15] = mock
            ? address(new MockRound16(address(mp), usdc))
            : address(new MoonpotRound16(address(mp), usdc));
        r[16] = mock
            ? address(new MockRound17(address(mp), usdc))
            : address(new MoonpotRound17(address(mp), usdc));
        r[17] = mock
            ? address(new MockRound18(address(mp), usdc))
            : address(new MoonpotRound18(address(mp), usdc));
        r[18] = mock
            ? address(new MockRound19(address(mp), usdc))
            : address(new MoonpotRound19(address(mp), usdc));
        r[19] = mock
            ? address(new MockRound20(address(mp), usdc))
            : address(new MoonpotRound20(address(mp), usdc));
        r[20] = mock
            ? address(new MockRound21(address(mp), usdc))
            : address(new MoonpotRound21(address(mp), usdc));
        r[21] = mock
            ? address(new MockRound22(address(mp), usdc))
            : address(new MoonpotRound22(address(mp), usdc));
        r[22] = mock
            ? address(new MockRound23(address(mp), usdc))
            : address(new MoonpotRound23(address(mp), usdc));
        r[23] = mock
            ? address(new MockRound24(address(mp), usdc))
            : address(new MoonpotRound24(address(mp), usdc));
        r[24] = mock
            ? address(new MockRound25(address(mp), usdc))
            : address(new MoonpotRound25(address(mp), usdc));
        r[25] = mock
            ? address(new MockRound26(address(mp), usdc))
            : address(new MoonpotRound26(address(mp), usdc));
        r[26] = mock
            ? address(new MockRound27(address(mp), usdc))
            : address(new MoonpotRound27(address(mp), usdc));
        r[27] = mock
            ? address(new MockRound28(address(mp), usdc))
            : address(new MoonpotRound28(address(mp), usdc));

        // 6. Wire managers + rounds.
        tmp.setManager(address(mp));
        nft.setManager(address(mp));
        hook.setManager(address(mp));
        nft.setBaseURI("https://api.themoonpot.com/nft/");
        for (uint256 i = 0; i < r.length; i++) {
            mp.setRound(i + 1, r[i]);
        }

        // 7. Seed the manager, create the pool, open round 1. The LP ceiling
        // tick is derived from the final round price x CEILING_MULTIPLIER,
        // sign-aware — no manual input, always the right sign for the ordering.
        uint256 finalPrice = IMoonpotRound(r[27]).getPricePerToken();
        int24 ceilingTick = _priceToTick(
            finalPrice * CEILING_MULTIPLIER,
            usdcIsToken0
        );
        IERC20(usdc).transfer(address(mp), initialUsdc);
        mp.init(initialUsdc, ceilingTick);
        mp.start();

        // 8. Hand all ownership to the Safe. Every contract is 2-step ownable
        // (OZ Ownable2Step / Chainlink ConfirmedOwner), so this only *proposes*
        // the Safe as owner — the Safe must then call acceptOwnership() on each.
        // Until it does, the deployer remains owner, so keep that key safe.
        if (safe != address(0)) {
            tmp.transferOwnership(safe);
            nft.transferOwnership(safe);
            hook.transferOwnership(safe);
            mp.transferOwnership(safe);
        }

        vm.stopBroadcast();

        // 9. Report.
        console.log(mock ? "=== MOCK deploy ===" : "=== PRODUCTION deploy ===");
        console.log("deployer        %s", deployer);
        console.log("company         %s", company);
        console.log("safe            %s", safe);
        console.log(
            "INITIAL USDC    %s USDC (%s base units)",
            initialUsdc / 1e6,
            initialUsdc
        );
        console.log("FINAL PRICE     %s (base units)", finalPrice);
        console.log("CEILING MULT    %s", CEILING_MULTIPLIER);
        console.log("VRF SUB ID      %s", vrfSubId);
        console.log("VRF COORD       %s", vrfCoordinator);
        console.log("VRF KEYHASH     %s", vm.toString(vrfKeyHash));
        console.log("usdcIsToken0    %s", usdcIsToken0);
        console.log("CEILING TICK    %s", vm.toString(int256(ceilingTick)));
        console.log("USDC            %s", usdc);
        console.log("TMP             %s", address(tmp));
        console.log("NFT             %s", address(nft));
        console.log("HOOK            %s", address(hook));
        console.log("MANAGER         %s", address(mp));
        (
            Currency c0,
            Currency c1,
            uint24 poolFee,
            int24 poolTickSpacing,
            IHooks poolHooks
        ) = mp.poolKey();
        PoolKey memory key = PoolKey(
            c0,
            c1,
            poolFee,
            poolTickSpacing,
            poolHooks
        );
        console.log(
            "POOL ID         %s",
            vm.toString(PoolId.unwrap(key.toId()))
        );
        for (uint256 i = 0; i < r.length; i++) {
            console.log(string.concat("ROUND", vm.toString(i + 1)), r[i]);
        }
        if (safe != address(0)) {
            console.log("OWNER -> SAFE   %s", safe);
            console.log(
                "ACTION: Safe must acceptOwnership() on TMP, NFT, HOOK, MANAGER"
            );
        }
    }
}
