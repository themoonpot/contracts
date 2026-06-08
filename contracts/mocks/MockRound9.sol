// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound9.sol";

/// @dev Test-only round. Inherits {MoonpotRound9} logic; only the contract
/// name differs. Not for production.
contract MockRound9 is MoonpotRound9 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound9(_manager, _usdc) {}
}
