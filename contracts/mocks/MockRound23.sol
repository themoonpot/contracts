// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound23.sol";

/// @dev Test-only round. Inherits {MoonpotRound23} logic; only the contract
/// name differs. Not for production.
contract MockRound23 is MoonpotRound23 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound23(_manager, _usdc) {}
}
