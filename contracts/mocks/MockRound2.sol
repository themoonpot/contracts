// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound2.sol";

/// @dev Test-only round. Inherits {MoonpotRound2} logic; only the contract
/// name differs. Not for production.
contract MockRound2 is MoonpotRound2 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound2(_manager, _usdc) {}
}
