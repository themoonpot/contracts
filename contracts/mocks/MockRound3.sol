// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound3.sol";

/// @dev Test-only round. Inherits {MoonpotRound3} logic; only the contract
/// name differs. Not for production.
contract MockRound3 is MoonpotRound3 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound3(_manager, _usdc) {}
}
