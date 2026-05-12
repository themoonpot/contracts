// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/MoonpotRound1.sol";
import "../contracts/MoonpotRound2.sol";
import "../contracts/MoonpotRound3.sol";
import "../contracts/MoonpotRound4.sol";
import "../contracts/MoonpotRound5.sol";
import "../contracts/AbstractMoonpotRound.sol";
import "../contracts/IMoonpotRound.sol";
import "../contracts/lib/TEAPermuter.sol";

contract MoonpotRound1Test is Test {
    MoonpotRound1 round;
    address manager = address(0xBEEF);
    address usdc = address(0xC0DE);

    function setUp() public {
        round = new MoonpotRound1(manager, usdc);
    }

    /* ---------------------------------- constructor ---------------------------------- */

    function testConstructorImmutables() public view {
        assertEq(round.roundId(), 1);
        assertEq(round.manager(), manager);
        assertEq(address(round.usdc()), usdc);
        assertEq(round.PRICE(), 1.15e6);
        assertEq(round.TOTAL_TOKENS(), 1_000_000);
        assertEq(round.TOTAL_NFTS(), 99_991);
        assertEq(round.SHARE_COMMUNITY(), 1.00e6);
        assertEq(round.SHARE_COMPANY(), 0.10e6);
        assertEq(round.SHARE_LIQUIDITY(), 0.05e6);
        // Shares sum to price (sanity check on contract math)
        assertEq(
            round.SHARE_COMMUNITY() + round.SHARE_COMPANY() + round.SHARE_LIQUIDITY(),
            round.PRICE()
        );
    }

    function testConstructorRevertsOnZeroManager() public {
        vm.expectRevert(AbstractMoonpotRound.InvalidAddress.selector);
        new MoonpotRound1(address(0), usdc);
    }

    function testConstructorRevertsOnZeroUsdc() public {
        vm.expectRevert(AbstractMoonpotRound.InvalidAddress.selector);
        new MoonpotRound1(manager, address(0));
    }

    /* ---------------------------------- reward table ---------------------------------- */

    function _expectTier(uint32 draw, IMoonpotRound.Class expectedClass, uint128 expectedValue) internal view {
        IMoonpotRound.NFTClass memory c = round.getNFTClass(draw);
        assertEq(uint256(c.classId), uint256(expectedClass), "wrong classId");
        assertEq(c.usdcValue, expectedValue, "wrong usdcValue");
    }

    function testTier1_draw0_top() public view {
        _expectTier(0, IMoonpotRound.Class.Class1, 100_000e6);
    }

    function testTier2_draws1to2() public view {
        _expectTier(1, IMoonpotRound.Class.Class2, 50_000e6);
        _expectTier(2, IMoonpotRound.Class.Class2, 50_000e6);
    }

    function testTier3_draws3to5() public view {
        _expectTier(3, IMoonpotRound.Class.Class3, 25_000e6);
        _expectTier(5, IMoonpotRound.Class.Class3, 25_000e6);
    }

    function testTier4_draws6to10() public view {
        _expectTier(6, IMoonpotRound.Class.Class4, 10_000e6);
        _expectTier(10, IMoonpotRound.Class.Class4, 10_000e6);
    }

    function testTier5_draws11to20() public view {
        _expectTier(11, IMoonpotRound.Class.Class5, 5_000e6);
        _expectTier(20, IMoonpotRound.Class.Class5, 5_000e6);
    }

    function testTier6_draws21to40() public view {
        _expectTier(21, IMoonpotRound.Class.Class6, 2_500e6);
        _expectTier(40, IMoonpotRound.Class.Class6, 2_500e6);
    }

    function testTier7_draws41to90() public view {
        _expectTier(41, IMoonpotRound.Class.Class7, 1_000e6);
        _expectTier(90, IMoonpotRound.Class.Class7, 1_000e6);
    }

    function testTier8_draws91to190() public view {
        _expectTier(91, IMoonpotRound.Class.Class8, 500e6);
        _expectTier(190, IMoonpotRound.Class.Class8, 500e6);
    }

    function testTier9_draws191to490() public view {
        _expectTier(191, IMoonpotRound.Class.Class9, 250e6);
        _expectTier(490, IMoonpotRound.Class.Class9, 250e6);
    }

    function testTier10_draws491to990() public view {
        _expectTier(491, IMoonpotRound.Class.Class10, 100e6);
        _expectTier(990, IMoonpotRound.Class.Class10, 100e6);
    }

    function testTier11_draws991to1990() public view {
        _expectTier(991, IMoonpotRound.Class.Class11, 50e6);
        _expectTier(1990, IMoonpotRound.Class.Class11, 50e6);
    }

    function testTier12_draws1991to4990() public view {
        _expectTier(1991, IMoonpotRound.Class.Class12, 25e6);
        _expectTier(4990, IMoonpotRound.Class.Class12, 25e6);
    }

    function testTier13_draws4991to9990() public view {
        _expectTier(4991, IMoonpotRound.Class.Class13, 10e6);
        _expectTier(9990, IMoonpotRound.Class.Class13, 10e6);
    }

    function testTier14_draws9991to19990() public view {
        _expectTier(9991, IMoonpotRound.Class.Class14, 5e6);
        _expectTier(19990, IMoonpotRound.Class.Class14, 5e6);
    }

    function testTier15_draws19991to49990() public view {
        _expectTier(19991, IMoonpotRound.Class.Class15, 2_500_000);
        _expectTier(49990, IMoonpotRound.Class.Class15, 2_500_000);
    }

    function testTier16_draws49991toLast() public view {
        _expectTier(49991, IMoonpotRound.Class.Class16, 1e6);
        _expectTier(99990, IMoonpotRound.Class.Class16, 1e6); // last valid draw
    }

    function testTierNone_outOfRange() public view {
        // draw == TOTAL_NFTS and beyond → Class.None, value 0
        _expectTier(99_991, IMoonpotRound.Class.None, 0);
        _expectTier(100_000, IMoonpotRound.Class.None, 0);
        _expectTier(type(uint32).max, IMoonpotRound.Class.None, 0);
    }

    /* ----- Reward pool conservation: sum of (count × value) per tier == 1,000,000 ----- */

    function testRewardPoolSumsToOneMillion() public view {
        uint256 sum;
        sum += 1 * 100_000e6; // Class1
        sum += 2 * 50_000e6; // Class2
        sum += 3 * 25_000e6; // Class3
        sum += 5 * 10_000e6; // Class4
        sum += 10 * 5_000e6; // Class5
        sum += 20 * 2_500e6; // Class6
        sum += 50 * 1_000e6; // Class7
        sum += 100 * 500e6; // Class8
        sum += 300 * 250e6; // Class9
        sum += 500 * 100e6; // Class10
        sum += 1_000 * 50e6; // Class11
        sum += 3_000 * 25e6; // Class12
        sum += 5_000 * 10e6; // Class13
        sum += 10_000 * 5e6; // Class14
        sum += 30_000 * 2_500_000; // Class15
        sum += 50_000 * 1e6; // Class16
        assertEq(sum, 1_000_000e6, "reward pool != $1,000,000");

        // And total NFTs in the table == TOTAL_NFTS
        uint32 total = 1 + 2 + 3 + 5 + 10 + 20 + 50 + 100 + 300 + 500 + 1_000 + 3_000 + 5_000 + 10_000 + 30_000 + 50_000;
        assertEq(total, round.TOTAL_NFTS());
    }

    /* --------------------------------- permute / valueOf --------------------------------- */

    function testPermuteInRange() public view {
        uint256 seed = 0xC0FFEE;
        for (uint256 i = 0; i < 100; i++) {
            uint256 out = round.permute(i, seed);
            assertLt(out, round.TOTAL_NFTS());
        }
    }

    function testPermuteDeterministic() public view {
        uint256 a = round.permute(42, 999);
        uint256 b = round.permute(42, 999);
        assertEq(a, b);
    }

    function testPermuteHandlesIndexModulo() public view {
        // index >= TOTAL_NFTS must still produce a valid output (uses index % TOTAL_NFTS)
        uint256 out = round.permute(round.TOTAL_NFTS() + 17, 123);
        assertLt(out, round.TOTAL_NFTS());
        // Same as the modulo'd index
        assertEq(out, round.permute(17, 123));
    }

    function testValueOfReturnsZeroBeforeSeed() public view {
        // seed defaults to 0; valueOf must short-circuit to (0,0,0)
        (uint256 value, uint8 classId, uint32 drawId) = round.valueOf(7);
        assertEq(value, 0);
        assertEq(classId, 0);
        assertEq(drawId, 0);
    }

    function testValueOfDeterministicAfterSeed() public {
        // Set the seed via the manager and confirm valueOf == lookup(permute(...))
        uint256 seed = 0xDEADBEEF;
        vm.prank(manager);
        round.setSeed(seed);

        uint256 tokenId = 12_345;
        (uint256 value, uint8 classId, uint32 drawId) = round.valueOf(tokenId);

        uint256 expectedDraw = round.permute(tokenId % round.TOTAL_TOKENS(), seed);
        IMoonpotRound.NFTClass memory expected = round.getNFTClass(uint32(expectedDraw));

        assertEq(drawId, uint32(expectedDraw));
        assertEq(value, expected.usdcValue);
        assertEq(classId, uint8(expected.classId));
    }

    /* ----- Rounds 2–5 share the same shape; smoke check each round's top + bottom tier ----- */

    function testRound2_topAndBottomTiers() public {
        MoonpotRound2 r2 = new MoonpotRound2(manager, usdc);
        IMoonpotRound.NFTClass memory top = r2.getNFTClass(0);
        assertEq(uint256(top.classId), uint256(IMoonpotRound.Class.Class1));
        assertEq(top.usdcValue, 200_000e6);
        IMoonpotRound.NFTClass memory bottom = r2.getNFTClass(99_990);
        assertEq(uint256(bottom.classId), uint256(IMoonpotRound.Class.Class16));
        assertEq(bottom.usdcValue, 2e6);
        assertEq(r2.roundId(), 2);
    }

    function testRound3_topAndBottomTiers() public {
        MoonpotRound3 r3 = new MoonpotRound3(manager, usdc);
        IMoonpotRound.NFTClass memory top = r3.getNFTClass(0);
        assertEq(top.usdcValue, 300_000e6);
        IMoonpotRound.NFTClass memory bottom = r3.getNFTClass(99_990);
        assertEq(bottom.usdcValue, 3e6);
        assertEq(r3.roundId(), 3);
    }

    function testRound4_topAndBottomTiers() public {
        MoonpotRound4 r4 = new MoonpotRound4(manager, usdc);
        IMoonpotRound.NFTClass memory top = r4.getNFTClass(0);
        assertEq(top.usdcValue, 400_000e6);
        IMoonpotRound.NFTClass memory bottom = r4.getNFTClass(99_990);
        assertEq(bottom.usdcValue, 4e6);
        assertEq(r4.roundId(), 4);
    }

    function testRound5_topAndBottomTiers() public {
        MoonpotRound5 r5 = new MoonpotRound5(manager, usdc);
        IMoonpotRound.NFTClass memory top = r5.getNFTClass(0);
        assertEq(top.usdcValue, 500_000e6);
        IMoonpotRound.NFTClass memory bottom = r5.getNFTClass(99_990);
        assertEq(bottom.usdcValue, 5e6);
        assertEq(r5.roundId(), 5);
    }
}
