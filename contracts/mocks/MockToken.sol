// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotToken.sol";

/// @dev Test-only token. Inherits {MoonpotToken} logic byte-for-byte; only the
/// display name/symbol and contract name differ, with nothing tying it to the
/// real project. Not for production.
contract MockToken is MoonpotToken {
    function name() public pure override returns (string memory) {
        return "Test Token";
    }

    function symbol() public pure override returns (string memory) {
        return "TST";
    }
}
