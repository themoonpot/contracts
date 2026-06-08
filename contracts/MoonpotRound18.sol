// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound18 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            18,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            1.20e6,
            /* Total Tokens */
            90_000_000,
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

        if (draw == 0) return NFTClass(Class.Class1, 9_000_000e6); // 1x $9,000,000
        if (draw <= 2) return NFTClass(Class.Class2, 4_500_000e6); // 2x $4,500,000
        if (draw <= 5) return NFTClass(Class.Class3, 2_250_000e6); // 3x $2,250,000
        if (draw <= 10) return NFTClass(Class.Class4, 900_000e6); // 5x $900,000
        if (draw <= 20) return NFTClass(Class.Class5, 450_000e6); // 10x $450,000
        if (draw <= 40) return NFTClass(Class.Class6, 225_000e6); // 20x $225,000
        if (draw <= 90) return NFTClass(Class.Class7, 90_000e6); // 50x $90,000
        if (draw <= 190) return NFTClass(Class.Class8, 45_000e6); // 100x $45,000
        if (draw <= 490) return NFTClass(Class.Class9, 22_500e6); // 300x $22,500
        if (draw <= 990) return NFTClass(Class.Class10, 9_000e6); // 500x $9,000
        if (draw <= 1990) return NFTClass(Class.Class11, 4_500e6); // 1_000x $4,500
        if (draw <= 4990) return NFTClass(Class.Class12, 2_250e6); // 3_000x $2,250
        if (draw <= 9990) return NFTClass(Class.Class13, 900e6); // 5_000x $900
        if (draw <= 19990) return NFTClass(Class.Class14, 450e6); // 10_000x $450
        if (draw <= 49990) return NFTClass(Class.Class15, 225_000_000); // 30_000x $225

        return NFTClass(Class.Class16, 90e6); // 50_000x $90
    }

    function permute(
        uint256 index,
        uint256 seed
    ) public view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 6);
    }
}
