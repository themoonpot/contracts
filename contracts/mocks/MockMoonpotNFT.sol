// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotNFT.sol";

/// @dev Test-only NFT. Identical logic to {MoonpotNFT} (inherited, not
/// re-implemented) with a distinct name/symbol so a mock deploy can never be
/// confused with the real collection. Not for production.
contract MockMoonpotNFT is MoonpotNFT {
    function name()
        public
        pure
        override(ERC721A, IERC721A)
        returns (string memory)
    {
        return "Moonpot Test NFT";
    }

    function symbol()
        public
        pure
        override(ERC721A, IERC721A)
        returns (string memory)
    {
        return "tTMPNFT";
    }
}
