// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound23 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            23,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            1.60e6,
            /* Total Tokens */
            500_000_000,
            /* Total NFTs */
            99_991,
            /* Share Community */
            1.00e6,
            /* Share Company */
            0.10e6,
            /* Share Liquidity */
            0.50e6
        )
    {}

    function getNFTClass(
        uint32 draw
    ) public view override returns (NFTClass memory) {
        if (draw >= TOTAL_NFTS) return NFTClass(Class.None, 0);

        if (draw == 0) return NFTClass(Class.Class1, 50_000_000e6); // 1x $50,000,000
        if (draw <= 2) return NFTClass(Class.Class2, 25_000_000e6); // 2x $25,000,000
        if (draw <= 5) return NFTClass(Class.Class3, 12_500_000e6); // 3x $12,500,000
        if (draw <= 10) return NFTClass(Class.Class4, 5_000_000e6); // 5x $5,000,000
        if (draw <= 20) return NFTClass(Class.Class5, 2_500_000e6); // 10x $2,500,000
        if (draw <= 40) return NFTClass(Class.Class6, 1_250_000e6); // 20x $1,250,000
        if (draw <= 90) return NFTClass(Class.Class7, 500_000e6); // 50x $500,000
        if (draw <= 190) return NFTClass(Class.Class8, 250_000e6); // 100x $250,000
        if (draw <= 490) return NFTClass(Class.Class9, 125_000e6); // 300x $125,000
        if (draw <= 990) return NFTClass(Class.Class10, 50_000e6); // 500x $50,000
        if (draw <= 1990) return NFTClass(Class.Class11, 25_000e6); // 1_000x $25,000
        if (draw <= 4990) return NFTClass(Class.Class12, 12_500e6); // 3_000x $12,500
        if (draw <= 9990) return NFTClass(Class.Class13, 5_000e6); // 5_000x $5,000
        if (draw <= 19990) return NFTClass(Class.Class14, 2_500e6); // 10_000x $2,500
        if (draw <= 49990) return NFTClass(Class.Class15, 1_250_000_000); // 30_000x $1,250

        return NFTClass(Class.Class16, 500e6); // 50_000x $500
    }

    function permute(
        uint256 index,
        uint256 seed
    ) public view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 6);
    }
}
