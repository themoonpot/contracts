// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound6.sol";

/// @dev Test-only round. Inherits {MoonpotRound6} logic; only the contract
/// name differs. Not for production.
contract MockRound6 is MoonpotRound6 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound6(_manager, _usdc) {}
}
