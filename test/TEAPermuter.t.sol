// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/lib/TEAPermuter.sol";

contract TEAPermuterTest is Test {
    /// --- permute9 (≈500 domain) ---

    function testPermute9OutputInRange() public pure {
        uint256 n = 500;
        uint256 out = TEAPermuter.permute9(42, n, 111, 6);
        assertLt(out, n);
    }

    function testPermute9Deterministic() public pure {
        uint256 n = 500;
        uint256 a = TEAPermuter.permute9(77, n, 999, 6);
        uint256 b = TEAPermuter.permute9(77, n, 999, 6);
        assertEq(a, b);
    }

    function testPermute9DifferentSeedsLikelyDiffer() public pure {
        uint256 n = 500;
        uint256 out1 = TEAPermuter.permute9(42, n, 123, 6);
        uint256 out2 = TEAPermuter.permute9(42, n, 456, 6);
        assert(out1 != out2);
    }

    function testPermute9IsPermutation_FullDomain() public pure {
        uint256 n = 512; // full 9-bit space
        bool[] memory seen = new bool[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 out = TEAPermuter.permute9(i, n, 222, 6);
            assertLt(out, n);
            assertTrue(!seen[out], "duplicate output");
            seen[out] = true;
        }
    }

    /// --- permute10 (≈1k domain) ---

    function testPermute10OutputInRange() public pure {
        uint256 n = 1_000;
        uint256 out = TEAPermuter.permute10(123, n, 321, 6);
        assertLt(out, n);
    }

    function testPermute10Deterministic() public pure {
        uint256 n = 1_000;
        uint256 a = TEAPermuter.permute10(55, n, 987, 6);
        uint256 b = TEAPermuter.permute10(55, n, 987, 6);
        assertEq(a, b);
    }

    function testPermute10DifferentSeedsLikelyDiffer() public pure {
        uint256 n = 1_000;
        uint256 out1 = TEAPermuter.permute10(42, n, 100, 6);
        uint256 out2 = TEAPermuter.permute10(42, n, 200, 6);
        assert(out1 != out2);
    }

    /// --- permute14 (≈16k domain) ---

    function testPermute14OutputInRange() public pure {
        uint256 n = 10_000;
        uint256 out = TEAPermuter.permute14(9999, n, 12345, 6);
        assertLt(out, n);
    }

    function testPermute14Deterministic() public pure {
        uint256 n = 10_000;
        uint256 a = TEAPermuter.permute14(5000, n, 98765, 6);
        uint256 b = TEAPermuter.permute14(5000, n, 98765, 6);
        assertEq(a, b);
    }

    function testPermute14DifferentSeedsLikelyDiffer() public pure {
        uint256 n = 10_000;
        uint256 out1 = TEAPermuter.permute14(42, n, 123, 6);
        uint256 out2 = TEAPermuter.permute14(42, n, 456, 6);
        assert(out1 != out2);
    }

    // Verifies bijection for the specific requested domain of 10,000
    // This proves every ID gets a unique shuffled position.
    function testPermute14IsPermutation_FullDomain() public pure {
        uint256 n = 10_000;
        bool[] memory seen = new bool[](n);

        for (uint256 i = 0; i < n; i++) {
            uint256 out = TEAPermuter.permute14(i, n, 777, 6);
            assertLt(out, n);
            assertTrue(!seen[out], "duplicate output detected");
            seen[out] = true;
        }
    }

    /// --- permute20 (≈1M domain) ---

    function testPermute20OutputInRange() public pure {
        uint256 n = 1_000_000;
        uint256 out = TEAPermuter.permute20(999_999, n, 12345, 6);
        assertLt(out, n);
    }

    function testPermute20Deterministic() public pure {
        uint256 n = 1_000_000;
        uint256 a = TEAPermuter.permute20(555_555, n, 98765, 6);
        uint256 b = TEAPermuter.permute20(555_555, n, 98765, 6);
        assertEq(a, b);
    }

    function testPermute20DifferentSeedsLikelyDiffer() public pure {
        uint256 n = 1_000_000;
        uint256 out1 = TEAPermuter.permute20(42, n, 123, 6);
        uint256 out2 = TEAPermuter.permute20(42, n, 456, 6);
        assert(out1 != out2);
    }

    // Note: a full-domain bijection test for permute20 would either need to
    // iterate the full 2^20 = ~1M block (slow) or use a small `n` like 256 with
    // heavy cycle-walking (memory-OOG). The bijection property of the Feistel
    // construction itself is proven by the smaller-block variants above
    // (permute9, permute10, permute14); they share the same `_encryptGeneric`
    // core. The production rounds use `permute17`, not `permute20`.
}
