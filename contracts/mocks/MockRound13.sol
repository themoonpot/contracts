// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound13.sol";

/// @dev Test-only round. Inherits {MoonpotRound13} logic; only the contract
/// name differs. Not for production.
contract MockRound13 is MoonpotRound13 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound13(_manager, _usdc) {}
}
