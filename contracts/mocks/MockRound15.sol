// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound15.sol";

/// @dev Test-only round. Inherits {MoonpotRound15} logic; only the contract
/// name differs. Not for production.
contract MockRound15 is MoonpotRound15 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound15(_manager, _usdc) {}
}
