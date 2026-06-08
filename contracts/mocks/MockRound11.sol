// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound11.sol";

/// @dev Test-only round. Inherits {MoonpotRound11} logic; only the contract
/// name differs. Not for production.
contract MockRound11 is MoonpotRound11 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound11(_manager, _usdc) {}
}
