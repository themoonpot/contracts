// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound17.sol";

/// @dev Test-only round. Inherits {MoonpotRound17} logic; only the contract
/// name differs. Not for production.
contract MockRound17 is MoonpotRound17 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound17(_manager, _usdc) {}
}
