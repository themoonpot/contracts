// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound25.sol";

/// @dev Test-only round. Inherits {MoonpotRound25} logic; only the contract
/// name differs. Not for production.
contract MockRound25 is MoonpotRound25 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound25(_manager, _usdc) {}
}
