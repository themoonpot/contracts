// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotNFT.sol";

/// @dev Test-only NFT. Inherits {MoonpotNFT} logic byte-for-byte; only the
/// display name/symbol and contract name differ. Not for production.
contract MockNFT is MoonpotNFT {
    function name()
        public
        pure
        override(ERC721A, IERC721A)
        returns (string memory)
    {
        return "Test NFT";
    }

    function symbol()
        public
        pure
        override(ERC721A, IERC721A)
        returns (string memory)
    {
        return "TSTN";
    }
}
