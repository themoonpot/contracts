// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound27 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            27,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            2.00e6,
            /* Total Tokens */
            900_000_000,
            /* Total NFTs */
            99_991,
            /* Share Community */
            1.00e6,
            /* Share Company */
            0.10e6,
            /* Share Liquidity */
            0.90e6
        )
    {}

    function getNFTClass(
        uint32 draw
    ) public view override returns (NFTClass memory) {
        if (draw >= TOTAL_NFTS) return NFTClass(Class.None, 0);

        if (draw == 0) return NFTClass(Class.Class1, 90_000_000e6); // 1x $90,000,000
        if (draw <= 2) return NFTClass(Class.Class2, 45_000_000e6); // 2x $45,000,000
        if (draw <= 5) return NFTClass(Class.Class3, 22_500_000e6); // 3x $22,500,000
        if (draw <= 10) return NFTClass(Class.Class4, 9_000_000e6); // 5x $9,000,000
        if (draw <= 20) return NFTClass(Class.Class5, 4_500_000e6); // 10x $4,500,000
        if (draw <= 40) return NFTClass(Class.Class6, 2_250_000e6); // 20x $2,250,000
        if (draw <= 90) return NFTClass(Class.Class7, 900_000e6); // 50x $900,000
        if (draw <= 190) return NFTClass(Class.Class8, 450_000e6); // 100x $450,000
        if (draw <= 490) return NFTClass(Class.Class9, 225_000e6); // 300x $225,000
        if (draw <= 990) return NFTClass(Class.Class10, 90_000e6); // 500x $90,000
        if (draw <= 1990) return NFTClass(Class.Class11, 45_000e6); // 1_000x $45,000
        if (draw <= 4990) return NFTClass(Class.Class12, 22_500e6); // 3_000x $22,500
        if (draw <= 9990) return NFTClass(Class.Class13, 9_000e6); // 5_000x $9,000
        if (draw <= 19990) return NFTClass(Class.Class14, 4_500e6); // 10_000x $4,500
        if (draw <= 49990) return NFTClass(Class.Class15, 2_250_000_000); // 30_000x $2,250

        return NFTClass(Class.Class16, 900e6); // 50_000x $900
    }

    function permute(
        uint256 index,
        uint256 seed
    ) public view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 6);
    }
}
