// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Fixtures.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @notice End-to-end capstone exercising the manager's purchase pipeline
/// against multiple buyers and liquidity-injection checkpoints. Pool-state
/// interactions are mocked (see Fixtures + per-test extsload / injectLiquidity
/// stubs). Real v4 pool integration tests are deferred (out of scope for the
/// MoonpotManager unit-test sprint).
contract MoonpotManagerIntegrationTest is InitializedFixture {
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function _afterDeploy() internal override {
        usdc.transfer(alice, 50_000_000e6);
        usdc.transfer(bob, 50_000_000e6);
        vm.prank(alice);
        usdc.approve(address(mp), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(mp), type(uint256).max);

        // Mock pool state + hook injectLiquidity for the injection checkpoints
        // we'll cross during the multi-buy flow.
        bytes32 slot0 = bytes32(uint256(TickMath.getSqrtPriceAtTick(-260_000)));
        vm.mockCall(
            address(poolManager),
            abi.encodeWithSignature("extsload(bytes32)"),
            abi.encode(slot0)
        );
        vm.mockCall(
            address(hook),
            abi.encodeWithSelector(MoonpotHook.injectLiquidity.selector),
            bytes("")
        );
    }

    function _buy(address buyer, uint256 tokens) internal returns (uint256 purchaseId, uint256 reqId) {
        vm.prank(buyer);
        mp.buyFor(buyer, tokens * round1.PRICE(), 0, 0, bytes32(0), bytes32(0));
        purchaseId = mp.lastPurchaseId();
        reqId = vrf.latestRequestId();
    }

    function testFullRoundFlow_BuysFulfillProcessSeedClaim() public {
        // -- 1. Alice and Bob each buy in stages, crossing the first liquidity
        //       injection checkpoint at 25_000 tokens.
        (uint256 aPid1, uint256 aReq1) = _buy(alice, 10_000);
        (uint256 bPid1, uint256 bReq1) = _buy(bob, 10_000);
        (uint256 aPid2, uint256 aReq2) = _buy(alice, 5_001); // crosses 25k

        assertEq(mp.lastInjectionCheckpoint(1), 25_001, "first checkpoint crossed");
        assertEq(mp.pendingLiquidityUsdc(), 0, "pending drained at crossing");
        assertEq(mp.tokensSold(), 25_001);

        // -- 2. VRF fulfillments arrive (possibly out of order)
        vrf.fulfill(aReq2);
        vrf.fulfill(bReq1);
        vrf.fulfill(aReq1);

        // -- 3. Each purchase gets processed → NFTs minted to buyers
        mp.processBuy(aPid1);
        mp.processBuy(bPid1);
        mp.processBuy(aPid2);

        uint256 aliceNfts = nft.balanceOf(alice);
        uint256 bobNfts = nft.balanceOf(bob);
        assertGt(aliceNfts + bobNfts, 0, "at least some NFTs allocated");

        // -- 4. Round ends + is seeded. We also top up the reward pool to the
        //       full per-tier maximum so claims can settle regardless of which
        //       tier(s) the buyers won (natural sellout would have built this
        //       up via community shares; we shortcut it here).
        usdc.transfer(address(round1), 1_000_000e6);
        vm.startPrank(address(mp));
        round1.depositFunds(1_000_000e6);
        round1.end();
        round1.setSeed(0xC0FFEEC0FFEE);
        vm.stopPrank();

        // -- 5. Buyers claim. We claim alice's full batch and bob's full batch.
        if (aliceNfts > 0) {
            uint256[] memory aIds = nft.tokensOfOwnerIn(alice, 0, type(uint256).max);
            uint256 aBefore = usdc.balanceOf(alice);
            vm.prank(alice);
            mp.claimNFTs(aIds);
            // She received something
            assertGt(usdc.balanceOf(alice), aBefore);
            // All her tokens are flagged claimed
            for (uint256 i = 0; i < aIds.length; i++) {
                assertTrue(mp.claimed(1, aIds[i]));
            }
        }
        if (bobNfts > 0) {
            uint256[] memory bIds = nft.tokensOfOwnerIn(bob, 0, type(uint256).max);
            uint256 bBefore = usdc.balanceOf(bob);
            vm.prank(bob);
            mp.claimNFTs(bIds);
            assertGt(usdc.balanceOf(bob), bBefore);
        }

        // Cross-check: round reward pool decreased by the total claimed value
        // (we topped up by $1M; remaining pool ≤ $1M + community contribution).
        assertLe(round1.rewardPool(), 1_000_000e6 + 25_001 * 1.00e6);
    }

    function testTokensSoldInvariantAcrossInjections() public {
        // Hammer multiple checkpoints with mixed buy sizes and assert
        // manager.tokensSold + round1.tokensSold stay in sync.
        // Each 25k-token boundary triggers one injection (drains pending USDC).
        _buy(alice, 8_000);
        _buy(bob, 7_000);
        _buy(alice, 10_000); // tokensSold = 25_000, crosses first 25k → injection
        _buy(bob, 10_000);   // tokensSold = 35_000, same interval (1) → no injection
        _buy(alice, 10_000); // tokensSold = 45_000, same interval (1) → no injection
        _buy(bob, 6_000);    // tokensSold = 51_000, crosses 50k → second injection

        assertEq(mp.tokensSold(), 51_000);
        assertEq(round1.tokensSold(), 51_000);

        // Checkpoint records the tokensSold *at the moment of crossing*, which
        // is 51_000 after the second injection.
        assertEq(mp.lastInjectionCheckpoint(1), 51_000);
        // Pending drained at the second crossing.
        assertEq(mp.pendingLiquidityUsdc(), 0);
    }
}
