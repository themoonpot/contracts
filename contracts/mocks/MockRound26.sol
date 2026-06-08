// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound26.sol";

/// @dev Test-only round. Inherits {MoonpotRound26} logic; only the contract
/// name differs. Not for production.
contract MockRound26 is MoonpotRound26 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound26(_manager, _usdc) {}
}
