// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound20.sol";

/// @dev Test-only round. Inherits {MoonpotRound20} logic; only the contract
/// name differs. Not for production.
contract MockRound20 is MoonpotRound20 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound20(_manager, _usdc) {}
}
