// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound4.sol";

/// @dev Test-only round. Identical logic to {MoonpotRound4} (inherited);
/// only the contract name differs. Not for production.
contract MockMoonpotRound4 is MoonpotRound4 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound4(_manager, _usdc) {}
}
