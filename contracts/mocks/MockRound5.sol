// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound5.sol";

/// @dev Test-only round. Inherits {MoonpotRound5} logic; only the contract
/// name differs. Not for production.
contract MockRound5 is MoonpotRound5 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound5(_manager, _usdc) {}
}
