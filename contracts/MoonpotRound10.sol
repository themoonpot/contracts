// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound10 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            10,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            1.20e6,
            /* Total Tokens */
            10_000_000,
            /* Total NFTs */
            99_991,
            /* Share Community */
            1.00e6,
            /* Share Company */
            0.10e6,
            /* Share Liquidity */
            0.10e6
        )
    {}

    function getNFTClass(
        uint32 draw
    ) public view override returns (NFTClass memory) {
        if (draw >= TOTAL_NFTS) return NFTClass(Class.None, 0);

        if (draw == 0) return NFTClass(Class.Class1, 1_000_000e6); // 1x $1,000,000
        if (draw <= 2) return NFTClass(Class.Class2, 500_000e6); // 2x $500,000
        if (draw <= 5) return NFTClass(Class.Class3, 250_000e6); // 3x $250,000
        if (draw <= 10) return NFTClass(Class.Class4, 100_000e6); // 5x $100,000
        if (draw <= 20) return NFTClass(Class.Class5, 50_000e6); // 10x $50,000
        if (draw <= 40) return NFTClass(Class.Class6, 25_000e6); // 20x $25,000
        if (draw <= 90) return NFTClass(Class.Class7, 10_000e6); // 50x $10,000
        if (draw <= 190) return NFTClass(Class.Class8, 5_000e6); // 100x $5,000
        if (draw <= 490) return NFTClass(Class.Class9, 2_500e6); // 300x $2,500
        if (draw <= 990) return NFTClass(Class.Class10, 1_000e6); // 500x $1,000
        if (draw <= 1990) return NFTClass(Class.Class11, 500e6); // 1_000x $500
        if (draw <= 4990) return NFTClass(Class.Class12, 250e6); // 3_000x $250
        if (draw <= 9990) return NFTClass(Class.Class13, 100e6); // 5_000x $100
        if (draw <= 19990) return NFTClass(Class.Class14, 50e6); // 10_000x $50
        if (draw <= 49990) return NFTClass(Class.Class15, 25_000_000); // 30_000x $25

        return NFTClass(Class.Class16, 10e6); // 50_000x $10
    }

    function permute(
        uint256 index,
        uint256 seed
    ) public view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 6);
    }
}
