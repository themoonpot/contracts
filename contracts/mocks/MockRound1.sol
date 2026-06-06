// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound1.sol";

/// @dev Test-only round. Inherits {MoonpotRound1} logic; only the contract
/// name differs. Not for production.
contract MockRound1 is MoonpotRound1 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound1(_manager, _usdc) {}
}
