// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound28.sol";

/// @dev Test-only round. Inherits {MoonpotRound28} logic; only the contract
/// name differs. Not for production.
contract MockRound28 is MoonpotRound28 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound28(_manager, _usdc) {}
}
