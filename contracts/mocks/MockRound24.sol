// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound24.sol";

/// @dev Test-only round. Inherits {MoonpotRound24} logic; only the contract
/// name differs. Not for production.
contract MockRound24 is MoonpotRound24 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound24(_manager, _usdc) {}
}
