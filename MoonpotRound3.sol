// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound3 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            3,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            1.15e6,
            /* Total Tokens */
            3_000_000,
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

        // Pool: $3,000,000
        if (draw == 0) return NFTClass(Class.Class1, 300_000e6); // 1x $300,000
        if (draw <= 2) return NFTClass(Class.Class2, 150_000e6); // 2x $150,000
        if (draw <= 5) return NFTClass(Class.Class3, 75_000e6); // 3x $75,000
        if (draw <= 10) return NFTClass(Class.Class4, 30_000e6); // 5x $30,000
        if (draw <= 20) return NFTClass(Class.Class5, 15_000e6); // 10x $15,000
        if (draw <= 40) return NFTClass(Class.Class6, 7_500e6); // 20x $7,500
        if (draw <= 90) return NFTClass(Class.Class7, 3_000e6); // 50x $3,000
        if (draw <= 190) return NFTClass(Class.Class8, 1_500e6); // 100x $1,500
        if (draw <= 490) return NFTClass(Class.Class9, 750e6); // 300x $750
        if (draw <= 990) return NFTClass(Class.Class10, 300e6); // 500x $300
        if (draw <= 1990) return NFTClass(Class.Class11, 150e6); // 1,000x $150
        if (draw <= 4990) return NFTClass(Class.Class12, 75e6); // 3,000x $75
        if (draw <= 9990) return NFTClass(Class.Class13, 30e6); // 5,000x $30
        if (draw <= 19990) return NFTClass(Class.Class14, 15e6); // 10,000x $15
        if (draw <= 49990) return NFTClass(Class.Class15, 7_500_000); // 30,000x $7,50

        return NFTClass(Class.Class16, 3e6); // 50,000x $3
    }

    function permute(
        uint256 index,
        uint256 seed
    ) external view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 4);
    }
}
