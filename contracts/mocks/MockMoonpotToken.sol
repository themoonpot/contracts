// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotToken.sol";

/// @dev Test-only token. Identical logic to {MoonpotToken} (inherited, not
/// re-implemented) with a distinct name/symbol so a mock deploy can never be
/// confused with the real TMP. Not for production.
contract MockMoonpotToken is MoonpotToken {
    function name() public pure override returns (string memory) {
        return "Moonpot Test Token";
    }

    function symbol() public pure override returns (string memory) {
        return "tTMP";
    }
}
