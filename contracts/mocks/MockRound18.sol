// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound18.sol";

/// @dev Test-only round. Inherits {MoonpotRound18} logic; only the contract
/// name differs. Not for production.
contract MockRound18 is MoonpotRound18 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound18(_manager, _usdc) {}
}
