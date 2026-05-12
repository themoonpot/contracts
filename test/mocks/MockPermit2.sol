// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Bare-minimum Permit2 stub: only satisfies the `approve` call that
/// MoonpotHook's constructor makes. Used by setter/quote unit tests where the
/// real Permit2 (pinned to solc 0.8.17) can't be imported directly. The Tier 2
/// fixture etches the real Permit2 bytecode at a fixed address for swap flows.
contract MockPermit2 {
    function approve(address, address, uint160, uint48) external {}
}
