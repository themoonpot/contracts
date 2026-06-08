// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound22.sol";

/// @dev Test-only round. Inherits {MoonpotRound22} logic; only the contract
/// name differs. Not for production.
contract MockRound22 is MoonpotRound22 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound22(_manager, _usdc) {}
}
