// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound4.sol";

/// @dev Test-only round. Inherits {MoonpotRound4} logic; only the contract
/// name differs. Not for production.
contract MockRound4 is MoonpotRound4 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound4(_manager, _usdc) {}
}
