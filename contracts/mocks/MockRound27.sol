// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound27.sol";

/// @dev Test-only round. Inherits {MoonpotRound27} logic; only the contract
/// name differs. Not for production.
contract MockRound27 is MoonpotRound27 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound27(_manager, _usdc) {}
}
