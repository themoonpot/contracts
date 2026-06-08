// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound21.sol";

/// @dev Test-only round. Inherits {MoonpotRound21} logic; only the contract
/// name differs. Not for production.
contract MockRound21 is MoonpotRound21 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound21(_manager, _usdc) {}
}
