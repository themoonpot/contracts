// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound16.sol";

/// @dev Test-only round. Inherits {MoonpotRound16} logic; only the contract
/// name differs. Not for production.
contract MockRound16 is MoonpotRound16 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound16(_manager, _usdc) {}
}
