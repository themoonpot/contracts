// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

import "../contracts/MoonpotHook.sol";
import "../contracts/MoonpotToken.sol";
import {Oracle} from "../contracts/lib/Oracle.sol";
import "../contracts/mocks/MockUSDC.sol";
import "./mocks/MockPermit2.sol";

/// @notice Exposes the hook's TWAP oracle + injection gate (F-2026-17061) for
/// unit testing without a live Uniswap pool. The gate logic takes `currentTick`
/// directly, so no PoolManager.getSlot0 mocking is needed.
contract OracleTestHook is MoonpotHook {
    constructor(
        IPoolManager _pm,
        address _posm,
        address _permit2,
        address _usdc,
        address _tmp,
        address _owner
    ) MoonpotHook(_pm, _posm, _permit2, _usdc, _tmp, _owner) {}

    function exposed_writeObservation(int24 tick) external {
        (observationIndex, observationCardinality) = Oracle.write(
            observations,
            observationIndex,
            uint32(block.timestamp),
            tick,
            1,
            observationCardinality,
            observationCardinalityNext
        );
    }

    function exposed_twapReady() external view returns (bool) {
        return _twapReady();
    }

    function exposed_consultTwapTick(int24 currentTick) external view returns (int24) {
        return _consultTwapTick(currentTick);
    }

    function exposed_injectionAllowedAt(int24 currentTick) external view returns (bool) {
        return _injectionAllowedAt(currentTick);
    }
}

contract MoonpotHookOracleTest is Test {
    uint160 constant HOOK_FLAGS =
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
    int24 constant TICK_SPACING = 60;

    MoonpotToken tmp;
    MockUSDC usdc;
    MockPermit2 permit2;

    function setUp() public {
        permit2 = new MockPermit2();
        tmp = new MoonpotToken();
        usdc = new MockUSDC();
        vm.warp(1_000_000); // keep block.timestamp > twapWindow for `observe`
    }

    function _deployHook() internal returns (OracleTestHook h) {
        bytes memory creationCode = type(OracleTestHook).creationCode;
        bytes memory args = abi.encode(
            IPoolManager(address(this)),
            address(permit2),
            address(permit2),
            address(usdc),
            address(tmp),
            address(this)
        );
        (address addr, bytes32 salt) = HookMiner.find(address(this), HOOK_FLAGS, creationCode, args);
        h = new OracleTestHook{salt: salt}(
            IPoolManager(address(this)),
            address(permit2),
            address(permit2),
            address(usdc),
            address(tmp),
            address(this)
        );
        require(address(h) == addr, "addr mismatch");
    }

    function _init(OracleTestHook h, bool usdcIsCurrency0) internal {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(usdcIsCurrency0 ? address(usdc) : address(tmp)),
            currency1: Currency.wrap(usdcIsCurrency0 ? address(tmp) : address(usdc)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(h))
        });
        h.beforeInitialize(address(this), key, 0); // also initializes the oracle
        h.setManager(address(this));
    }

    /* ------------------------------- TWAP gate --------------------------------------- */

    function testTwapGateAroundDeviationBand() public {
        OracleTestHook h = _deployHook();
        _init(h, true);
        h.growOracle(1024);

        // Build a full window of history at a constant tick T (last write at `now`).
        // NB: use an explicit time accumulator — re-reading block.timestamp in a
        // loop is cached under via_ir, so vm.warp(block.timestamp + n) would stall.
        int24 T = 1_000;
        uint256 t = block.timestamp;
        for (uint256 i = 0; i < 25; i++) {
            t += 100;
            vm.warp(t);
            h.exposed_writeObservation(T);
        }

        assertTrue(h.exposed_twapReady(), "oracle should be warm");
        assertEq(h.exposed_consultTwapTick(T), T, "TWAP should equal the constant tick");

        uint24 maxDev = h.maxTwapDeviationTicks(); // 1000
        // within band (incl. boundary) -> allowed
        assertTrue(h.exposed_injectionAllowedAt(T));
        assertTrue(h.exposed_injectionAllowedAt(T + int24(int256(uint256(maxDev)))));
        assertTrue(h.exposed_injectionAllowedAt(T - int24(int256(uint256(maxDev)))));
        // beyond band -> deferred
        assertFalse(h.exposed_injectionAllowedAt(T + int24(int256(uint256(maxDev))) + 1));
        assertFalse(h.exposed_injectionAllowedAt(T - int24(int256(uint256(maxDev))) - 1));
    }

    /* --------------------------- warm-up floor-band ---------------------------------- */

    function testFloorBandWhenTwapNotReady_usdcCurrency0() public {
        OracleTestHook h = _deployHook();
        _init(h, true);
        h.setCurrentFloorTick(1_000);

        assertFalse(h.exposed_twapReady(), "fresh oracle is not warm");

        // usdc currency0: higher tick = lower TMP price; floor band is BELOW the floor tick.
        assertTrue(h.exposed_injectionAllowedAt(1_000 - 1_000)); // within band above floor
        assertFalse(h.exposed_injectionAllowedAt(1_000 - 3_000)); // too far above floor
        assertFalse(h.exposed_injectionAllowedAt(1_000 + 100)); // below floor
    }

    function testFloorBandWhenTwapNotReady_usdcCurrency1() public {
        OracleTestHook h = _deployHook();
        _init(h, false);
        h.setCurrentFloorTick(1_000);

        assertFalse(h.exposed_twapReady());

        // tmp currency0: higher tick = higher TMP price; floor band is ABOVE the floor tick.
        assertTrue(h.exposed_injectionAllowedAt(1_000 + 1_000));
        assertFalse(h.exposed_injectionAllowedAt(1_000 + 3_000));
        assertFalse(h.exposed_injectionAllowedAt(1_000 - 100));
    }
}
