// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound5 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            5,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            1.15e6,
            /* Total Tokens */
            5_000_000,
            /* Total NFTs */
            99_991,
            /* Share Community */
            1.00e6,
            /* Share Company */
            0.10e6,
            /* Share Liquidity */
            0.05e6
        )
    {}

    function getNFTClass(
        uint32 draw
    ) external view override returns (NFTClass memory) {
        if (draw >= TOTAL_NFTS) return NFTClass(Class.None, 0);

        // Pool: $5,000,000
        if (draw == 0) return NFTClass(Class.Class1, 500_000e6); // 1x $500,000
        if (draw <= 2) return NFTClass(Class.Class2, 250_000e6); // 2x $250,000
        if (draw <= 5) return NFTClass(Class.Class3, 125_000e6); // 3x $125,000
        if (draw <= 10) return NFTClass(Class.Class4, 50_000e6); // 5x $50,000
        if (draw <= 20) return NFTClass(Class.Class5, 25_000e6); // 10x $25,000
        if (draw <= 40) return NFTClass(Class.Class6, 12_500e6); // 20x $12,500
        if (draw <= 90) return NFTClass(Class.Class7, 5_000e6); // 50x $5,000
        if (draw <= 190) return NFTClass(Class.Class8, 2_500e6); // 100x $2,500
        if (draw <= 490) return NFTClass(Class.Class9, 1_250e6); // 300x $1,250
        if (draw <= 990) return NFTClass(Class.Class10, 500e6); // 500x $500
        if (draw <= 1990) return NFTClass(Class.Class11, 250e6); // 1,000x $250
        if (draw <= 4990) return NFTClass(Class.Class12, 125e6); // 3,000x $125
        if (draw <= 9990) return NFTClass(Class.Class13, 50e6); // 5,000x $50
        if (draw <= 19990) return NFTClass(Class.Class14, 25e6); // 10,000x $25
        if (draw <= 49990) return NFTClass(Class.Class15, 12_500_000); // 30,000x $12,50

        return NFTClass(Class.Class16, 5e6); // 50,000x $5
    }

    function permute(
        uint256 index,
        uint256 seed
    ) external view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 4);
    }
}
