// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound9 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            9,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            1.15e6,
            /* Total Tokens */
            9_000_000,
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
    ) public view override returns (NFTClass memory) {
        if (draw >= TOTAL_NFTS) return NFTClass(Class.None, 0);

        if (draw == 0) return NFTClass(Class.Class1, 900_000e6); // 1x $900,000
        if (draw <= 2) return NFTClass(Class.Class2, 450_000e6); // 2x $450,000
        if (draw <= 5) return NFTClass(Class.Class3, 225_000e6); // 3x $225,000
        if (draw <= 10) return NFTClass(Class.Class4, 90_000e6); // 5x $90,000
        if (draw <= 20) return NFTClass(Class.Class5, 45_000e6); // 10x $45,000
        if (draw <= 40) return NFTClass(Class.Class6, 22_500e6); // 20x $22,500
        if (draw <= 90) return NFTClass(Class.Class7, 9_000e6); // 50x $9,000
        if (draw <= 190) return NFTClass(Class.Class8, 4_500e6); // 100x $4,500
        if (draw <= 490) return NFTClass(Class.Class9, 2_250e6); // 300x $2,250
        if (draw <= 990) return NFTClass(Class.Class10, 900e6); // 500x $900
        if (draw <= 1990) return NFTClass(Class.Class11, 450e6); // 1_000x $450
        if (draw <= 4990) return NFTClass(Class.Class12, 225e6); // 3_000x $225
        if (draw <= 9990) return NFTClass(Class.Class13, 90e6); // 5_000x $90
        if (draw <= 19990) return NFTClass(Class.Class14, 45e6); // 10_000x $45
        if (draw <= 49990) return NFTClass(Class.Class15, 22_500_000); // 30_000x $22.50

        return NFTClass(Class.Class16, 9e6); // 50_000x $9
    }

    function permute(
        uint256 index,
        uint256 seed
    ) public view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 6);
    }
}
