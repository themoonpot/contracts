// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound1.sol";

/// @dev Test-only round. Identical logic to {MoonpotRound1} (inherited);
/// only the contract name differs. Not for production.
contract MockMoonpotRound1 is MoonpotRound1 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound1(_manager, _usdc) {}
}
