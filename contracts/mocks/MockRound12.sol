// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound12.sol";

/// @dev Test-only round. Inherits {MoonpotRound12} logic; only the contract
/// name differs. Not for production.
contract MockRound12 is MoonpotRound12 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound12(_manager, _usdc) {}
}
