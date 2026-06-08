// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound10.sol";

/// @dev Test-only round. Inherits {MoonpotRound10} logic; only the contract
/// name differs. Not for production.
contract MockRound10 is MoonpotRound10 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound10(_manager, _usdc) {}
}
