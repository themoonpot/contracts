// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound7.sol";

/// @dev Test-only round. Inherits {MoonpotRound7} logic; only the contract
/// name differs. Not for production.
contract MockRound7 is MoonpotRound7 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound7(_manager, _usdc) {}
}
