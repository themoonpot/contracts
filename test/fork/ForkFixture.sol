// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import "../../contracts/MoonpotHook.sol";
import "../../contracts/MoonpotManager.sol";
import "../../contracts/MoonpotToken.sol";
import "../../contracts/MoonpotNFT.sol";
import "../../contracts/MoonpotRound1.sol";
import "../../contracts/MoonpotRound2.sol";
import "../../contracts/MoonpotRound3.sol";
import "../../contracts/MoonpotRound4.sol";
import "../../contracts/MoonpotRound5.sol";
import "../../contracts/mocks/MockVRFCoordinator.sol";

/// @notice Base-mainnet fork fixture for Hook tests that need real Uniswap v4
/// state (`beforeSwap`, `injectLiquidity`, `harvestFees`).
///
/// Deploys a fresh Moonpot system into a forked Base mainnet at a pinned block,
/// reusing the real `PoolManager`, `PositionManager`, `Permit2`, and `USDC`
/// contracts at their canonical addresses. Override the fork RPC and block via
/// env vars when running locally:
///
///     BASE_RPC_URL=https://alchemy.../v2/<key> \
///     BASE_FORK_BLOCK=33000000 \
///     forge test --match-path "test/fork/*.fork.t.sol"
///
/// If `BASE_RPC_URL` is unset, the public Base RPC defined in foundry.toml is
/// used. If the fork can't be created (no network, invalid block, etc.) the
/// fixture calls `vm.skip(true)` so the rest of the suite still passes.
abstract contract ForkFixture is Test {
    using PoolIdLibrary for PoolKey;

    // Canonical Base mainnet addresses
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint160 constant HOOK_FLAGS =
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

    address constant COMPANY = address(0xC0C0);
    bytes32 constant VRF_KEY = bytes32(uint256(0xAA));
    uint256 constant VRF_SUB = 1;

    // Default starter liquidity ($100k); smaller than mainnet's $1M to keep
    // fork-test fixture state manageable. Configurable via BASE_FORK_USDC.
    uint256 constant DEFAULT_INITIAL_USDC = 100_000e6;

    // Default fork block. The protocol's v4 deps (PoolManager, PositionManager,
    // Permit2) have all been live on Base since Q1 2025; any reasonably recent
    // block works. Override with `BASE_FORK_BLOCK` env var.
    uint256 constant DEFAULT_FORK_BLOCK = 33_000_000;

    // Real v4 / Permit2 / USDC handles (cast to interfaces; live contracts on the fork)
    IPoolManager poolManager;
    IPositionManager positionManager;

    // Deployed Moonpot system (fresh per test)
    MoonpotHook hook;
    MoonpotManager mp;
    MoonpotToken tmp;
    MoonpotNFT nft;
    DeployableVRFCoordinatorV2_5Mock vrf;
    MoonpotRound1 round1;
    MoonpotRound2 round2;
    MoonpotRound3 round3;
    MoonpotRound4 round4;
    MoonpotRound5 round5;
    PoolKey poolKey;
    PoolId poolId;

    uint256 internal initialUsdc;

    function setUp() public virtual {
        // --- 1. Establish the fork (skip the whole test if not available) ---
        try this._createFork() {
            // ok
        } catch {
            vm.skip(true);
            return;
        }

        poolManager = IPoolManager(POOL_MANAGER);
        positionManager = IPositionManager(POSITION_MANAGER);

        initialUsdc = vm.envOr("BASE_FORK_USDC", DEFAULT_INITIAL_USDC);

        // --- 2. Deploy fresh Moonpot tokens, NFT, VRF mock ---
        tmp = new MoonpotToken();
        nft = new MoonpotNFT();
        vrf = new DeployableVRFCoordinatorV2_5Mock();

        // --- 3. Mine + deploy the hook against the real PoolManager ---
        bytes memory creationCode = type(MoonpotHook).creationCode;
        bytes memory args = abi.encode(
            poolManager,
            POSITION_MANAGER,
            PERMIT2,
            USDC,
            address(tmp),
            address(this)
        );
        (address hookAddr, bytes32 salt) = HookMiner.find(address(this), HOOK_FLAGS, creationCode, args);
        hook = new MoonpotHook{salt: salt}(
            poolManager,
            POSITION_MANAGER,
            PERMIT2,
            USDC,
            address(tmp),
            address(this)
        );
        require(address(hook) == hookAddr, "hook addr mismatch");

        // --- 4. Deploy the manager and rounds, wire everything ---
        mp = new MoonpotManager(
            USDC,
            address(tmp),
            address(nft),
            COMPANY,
            address(vrf),
            VRF_KEY,
            VRF_SUB,
            POOL_MANAGER,
            POSITION_MANAGER,
            PERMIT2,
            address(hook)
        );

        round1 = new MoonpotRound1(address(mp), USDC);
        round2 = new MoonpotRound2(address(mp), USDC);
        round3 = new MoonpotRound3(address(mp), USDC);
        round4 = new MoonpotRound4(address(mp), USDC);
        round5 = new MoonpotRound5(address(mp), USDC);

        tmp.setManager(address(mp));
        nft.setManager(address(mp));
        hook.setManager(address(mp));
        mp.setRound(1, address(round1));
        mp.setRound(2, address(round2));
        mp.setRound(3, address(round3));
        mp.setRound(4, address(round4));
        mp.setRound(5, address(round5));

        // --- 5. Fund the manager with USDC (via forge-std `deal`) and init ---
        deal(USDC, address(mp), initialUsdc);
        _initSystem();

        _afterInit();
    }

    /// @dev Wraps `vm.createSelectFork` in an external function so its revert
    /// can be caught by `try/catch` in setUp.
    function _createFork() external {
        string memory rpc = vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org"));
        uint256 forkBlock = vm.envOr("BASE_FORK_BLOCK", DEFAULT_FORK_BLOCK);
        vm.createSelectFork(rpc, forkBlock);
    }

    /// @dev Calls `mp.init` and `mp.start`. Split out so subclasses can adjust
    /// (e.g. pre-deal USDC to test accounts before init).
    function _initSystem() internal virtual {
        // Compute a ceiling tick high above the round-1 floor. Round-1 price
        // is $1.15; with the manager's CEILING_MULTIPLIER-equivalent logic from
        // calculate-ceiling-tick.ts (10× last-round-price), a ceiling near
        // -245880 is what mainnet uses.
        int24 ceilingTick = -245_880;
        mp.init(initialUsdc, ceilingTick);
        mp.start();

        poolKey = _readPoolKey();
        poolId = poolKey.toId();
    }

    /// @dev Override in subclasses to seed buyers / mine more state before
    /// individual tests run.
    function _afterInit() internal virtual {}

    /// @dev The hook's `poolKey` is set by `beforeInitialize`. Re-read it for
    /// convenience.
    function _readPoolKey() internal view returns (PoolKey memory key) {
        (Currency c0, Currency c1, uint24 fee, int24 tickSpacing, IHooks h) = hook.poolKey();
        key = PoolKey({currency0: c0, currency1: c1, fee: fee, tickSpacing: tickSpacing, hooks: h});
    }

    /// @dev True when USDC is currency0 in the pool key. On Base, USDC's
    /// address compares less than TMP's (computed fresh), so this is always
    /// true for our deployments here, but we read it from the pool key to be
    /// safe.
    function _usdcIsCurrency0() internal view returns (bool) {
        return Currency.unwrap(poolKey.currency0) == USDC;
    }
}
