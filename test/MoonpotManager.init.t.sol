// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Fixtures.sol";

contract MoonpotManagerInitTest is BaseFixture {
    function testInitHappyPath() public {
        // Fund and call init
        usdc.transfer(address(mp), INITIAL_USDC);
        mp.init(INITIAL_USDC, CEILING_TICK);

        // Manager flags
        assertTrue(mp.isInitialized());

        // Pool key wired with the right currencies and tickSpacing
        (, , uint24 fee, int24 tickSpacing, ) = mp.poolKey();
        // Dynamic-fee flag is `uint24(1 << 23) | 0`; just sanity-check tickSpacing.
        assertEq(tickSpacing, 60);
        assertTrue(fee != 0);

        // Hook armed via setPosition
        assertEq(hook.positionId(), 1); // mocked nextTokenId returns 2 → id = 1
        assertGt(hook.protocolLiquidity(), 0);
        assertGt(hook.positionTickUpper(), hook.positionTickLower());

        // Manager mints TMP for the LP and then burns whatever the mocked
        // PositionManager didn't pull. Net: manager holds zero TMP after init.
        assertEq(tmp.balanceOf(address(mp)), 0);

        // pendingLiquidityUsdc stays 0 (only buys add to it)
        assertEq(mp.pendingLiquidityUsdc(), 0);
    }

    function testInitRevertsOnSecondCall() public {
        usdc.transfer(address(mp), INITIAL_USDC);
        mp.init(INITIAL_USDC, CEILING_TICK);
        vm.expectRevert(MoonpotManager.AlreadyInitialized.selector);
        mp.init(INITIAL_USDC, CEILING_TICK);
    }

    function testInitRevertsOnMisalignedCeilingTick() public {
        usdc.transfer(address(mp), INITIAL_USDC);
        // ceilingTick must be aligned to tickSpacing (60); -245_879 is not (F-2026-17179).
        vm.expectRevert(MoonpotManager.InvalidTickBound.selector);
        mp.init(INITIAL_USDC, -245_879);
    }

    function testInitOnlyOwner() public {
        usdc.transfer(address(mp), INITIAL_USDC);
        vm.expectRevert(); // Chainlink ConfirmedOwner
        vm.prank(address(0xBAD));
        mp.init(INITIAL_USDC, CEILING_TICK);
    }

    function testInitMintsAndBurnsTMP() public {
        // Before init, no TMP exists
        assertEq(tmp.totalSupply(), 0);

        usdc.transfer(address(mp), INITIAL_USDC);
        mp.init(INITIAL_USDC, CEILING_TICK);

        // After init: the mock PositionManager didn't pull any TMP, so all the
        // minted TMP was burned by the leftover-cleanup branch.
        // Net supply is 0 (mint, then burn).
        assertEq(tmp.totalSupply(), 0);
    }

    function testInitSetsFloorTickOnHook() public {
        usdc.transfer(address(mp), INITIAL_USDC);
        mp.init(INITIAL_USDC, CEILING_TICK);

        // init() now configures the floor band itself, so the pool is never
        // live+funded with the zero-default floor before start() (F-2026-17240).
        int24 floorAfterInit = hook.currentFloorTick();
        assertTrue(floorAfterInit != 0);
        assertTrue(hook.floorTickSet());
        // floorTickLower/Upper widen by poolKey.tickSpacing; but our stub
        // PoolManager never received a `beforeInitialize`, so the hook's
        // poolKey.tickSpacing remains 0 in this fixture. Bounds therefore
        // collapse onto currentFloorTick.
        assertEq(hook.floorTickLower(), floorAfterInit);
        assertEq(hook.floorTickUpper(), floorAfterInit);

        mp.start();
        // start() for round 1 derives the floor from the same round-1 price, so
        // the value is unchanged.
        assertEq(hook.currentFloorTick(), floorAfterInit);
    }
}

/// @dev Custom fixture that omits the round-1 wiring so we can test the
/// `RoundMissing` revert path.
contract MoonpotManagerInitNoRoundTest is BaseFixture {
    function _afterDeploy() internal override {
        // Tear down the round-1 wiring set by BaseFixture.setUp().
        // We do this via storage manipulation since `rounds` mapping has no
        // unset method on the manager.
        // Manager.rounds is at slot calculated from the storage layout; too
        // brittle to compute. Instead, deploy a *new* manager without round
        // wiring. We re-use the same hook/tokens/etc.
    }

    function testInitRevertsWhenRound1Missing() public {
        // Deploy a fresh Manager with no rounds wired
        MoonpotManager mp2 = new MoonpotManager(
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

        usdc.transfer(address(mp2), INITIAL_USDC);
        vm.expectRevert(MoonpotManager.RoundMissing.selector);
        mp2.init(INITIAL_USDC, CEILING_TICK);
    }
}
