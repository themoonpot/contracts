// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound14.sol";

/// @dev Test-only round. Inherits {MoonpotRound14} logic; only the contract
/// name differs. Not for production.
contract MockRound14 is MoonpotRound14 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound14(_manager, _usdc) {}
}
