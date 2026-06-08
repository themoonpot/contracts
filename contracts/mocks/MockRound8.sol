// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound8.sol";

/// @dev Test-only round. Inherits {MoonpotRound8} logic; only the contract
/// name differs. Not for production.
contract MockRound8 is MoonpotRound8 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound8(_manager, _usdc) {}
}
