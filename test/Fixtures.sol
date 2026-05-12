// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
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
import "./mocks/MockPermit2.sol";

/// @notice Base test fixture for MoonpotManager-centric Tier 2 tests.
///
/// Wires up the full Moonpot system against a **real PoolManager** and **mocked
/// PositionManager + Permit2** (see scope decision in the plan file). The
/// `positionManager` calls are intercepted via `vm.mockCall`:
/// - `multicall(bytes[])` is a no-op returning empty bytes[]
/// - `nextTokenId()` returns 2 so the manager's `init` flow yields positionId 1
///
/// This is sufficient for testing the Manager's bookkeeping (token mints,
/// approvals, share routing, VRF requests, NFT allocation, claims) without
/// pulling in v4-periphery's PositionManager (pragma 0.8.26) which is
/// version-incompatible with our 0.8.28 test contracts. Hook-pool interactions
/// that genuinely depend on v4 pool state are mocked per-test with
/// `vm.mockCall` on the PoolManager's `extsload`.
abstract contract BaseFixture is Test {
    uint160 constant HOOK_FLAGS =
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

    address constant COMPANY = address(0xC0C0);
    bytes32 constant VRF_KEY = bytes32(uint256(0xAA));
    uint256 constant VRF_SUB = 1;
    uint256 constant INITIAL_USDC = 1_000_000e6; // $1M starter liquidity
    int24 constant CEILING_TICK = -245_880; // from mainnet ignition params

    // Stub address for the PositionManager; never deployed; all calls
    // intercepted via vm.mockCall.
    address positionManager;

    MockUSDC usdc;
    MoonpotToken tmp;
    MoonpotNFT nft;
    DeployableVRFCoordinatorV2_5Mock vrf;
    MockPermit2 permit2;
    IPoolManager poolManager;
    MoonpotHook hook;
    MoonpotManager mp;
    MoonpotRound1 round1;
    MoonpotRound2 round2;
    MoonpotRound3 round3;
    MoonpotRound4 round4;
    MoonpotRound5 round5;

    function setUp() public virtual {
        // 1. Tokens and mocks
        usdc = new MockUSDC();
        tmp = new MoonpotToken();
        nft = new MoonpotNFT();
        vrf = new DeployableVRFCoordinatorV2_5Mock();
        permit2 = new MockPermit2();

        // 2. Stub PoolManager; v4-core's PoolManager pins solc 0.8.26 and
        //    can't be imported directly. The Manager and Hook constructors
        //    only store the address; calls into it during buyFor / hook flows
        //    are mocked per-test with `vm.mockCall` (see helpers below).
        poolManager = IPoolManager(makeAddr("poolManager"));

        // 3. Stub PositionManager; mocked entirely via vm.mockCall
        positionManager = makeAddr("positionManager");
        // multicall(bytes[]): no-op, returns empty bytes[]
        bytes[] memory emptyResults;
        vm.mockCall(
            positionManager,
            abi.encodeWithSignature("multicall(bytes[])"),
            abi.encode(emptyResults)
        );
        // nextTokenId(): returns 2 so the manager computes positionId = 1
        vm.mockCall(
            positionManager,
            abi.encodeWithSignature("nextTokenId()"),
            abi.encode(uint256(2))
        );

        // 4. Mine hook salt and deploy
        bytes memory creationCode = type(MoonpotHook).creationCode;
        bytes memory args = abi.encode(
            poolManager,
            positionManager,
            address(permit2),
            address(usdc),
            address(tmp),
            address(this)
        );
        (address hookAddr, bytes32 salt) = HookMiner.find(address(this), HOOK_FLAGS, creationCode, args);
        hook = new MoonpotHook{salt: salt}(
            poolManager,
            positionManager,
            address(permit2),
            address(usdc),
            address(tmp),
            address(this)
        );
        require(address(hook) == hookAddr, "hook addr mismatch");

        // 5. Deploy MoonpotManager
        mp = new MoonpotManager(
            address(usdc),
            address(tmp),
            address(nft),
            COMPANY,
            address(vrf),
            VRF_KEY,
            VRF_SUB,
            address(poolManager),
            positionManager,
            address(permit2),
            address(hook)
        );

        // 6. Deploy rounds 1..5
        round1 = new MoonpotRound1(address(mp), address(usdc));
        round2 = new MoonpotRound2(address(mp), address(usdc));
        round3 = new MoonpotRound3(address(mp), address(usdc));
        round4 = new MoonpotRound4(address(mp), address(usdc));
        round5 = new MoonpotRound5(address(mp), address(usdc));

        // 7. Wire setManager / setRound
        tmp.setManager(address(mp));
        nft.setManager(address(mp));
        hook.setManager(address(mp));
        mp.setRound(1, address(round1));
        mp.setRound(2, address(round2));
        mp.setRound(3, address(round3));
        mp.setRound(4, address(round4));
        mp.setRound(5, address(round5));

        // 8. Optional fixture hook
        _afterDeploy();
    }

    /// @dev Override in subclasses to customize fixture state before tests run.
    function _afterDeploy() internal virtual {}

    /// @dev Helper: fulfill the most-recent VRF request via the mock coordinator.
    function _fulfillLatestVRF() internal {
        uint256 reqId = vrf.latestRequestId();
        vrf.fulfill(reqId);
    }
}

/// @notice Extends BaseFixture by funding the manager and running `init` + `start`.
/// Used by every test that needs an active round-1 state.
abstract contract InitializedFixture is BaseFixture {
    function setUp() public virtual override {
        super.setUp();

        // Fund the manager with $1M USDC (used by `init` as starter liquidity)
        usdc.transfer(address(mp), INITIAL_USDC);

        // Initialize the system: mints starter TMP, opens LP position, arms hook
        mp.init(INITIAL_USDC, CEILING_TICK);

        // Start round 1
        mp.start();
    }
}
