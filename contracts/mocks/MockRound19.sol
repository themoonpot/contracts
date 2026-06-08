// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound19.sol";

/// @dev Test-only round. Inherits {MoonpotRound19} logic; only the contract
/// name differs. Not for production.
contract MockRound19 is MoonpotRound19 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound19(_manager, _usdc) {}
}
