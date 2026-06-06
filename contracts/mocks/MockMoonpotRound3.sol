// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotRound3.sol";

/// @dev Test-only round. Identical logic to {MoonpotRound3} (inherited);
/// only the contract name differs. Not for production.
contract MockMoonpotRound3 is MoonpotRound3 {
    constructor(
        address _manager,
        address _usdc
    ) MoonpotRound3(_manager, _usdc) {}
}
