// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound16 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            16,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            1.20e6,
            /* Total Tokens */
            70_000_000,
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

        if (draw == 0) return NFTClass(Class.Class1, 7_000_000e6); // 1x $7,000,000
        if (draw <= 2) return NFTClass(Class.Class2, 3_500_000e6); // 2x $3,500,000
        if (draw <= 5) return NFTClass(Class.Class3, 1_750_000e6); // 3x $1,750,000
        if (draw <= 10) return NFTClass(Class.Class4, 700_000e6); // 5x $700,000
        if (draw <= 20) return NFTClass(Class.Class5, 350_000e6); // 10x $350,000
        if (draw <= 40) return NFTClass(Class.Class6, 175_000e6); // 20x $175,000
        if (draw <= 90) return NFTClass(Class.Class7, 70_000e6); // 50x $70,000
        if (draw <= 190) return NFTClass(Class.Class8, 35_000e6); // 100x $35,000
        if (draw <= 490) return NFTClass(Class.Class9, 17_500e6); // 300x $17,500
        if (draw <= 990) return NFTClass(Class.Class10, 7_000e6); // 500x $7,000
        if (draw <= 1990) return NFTClass(Class.Class11, 3_500e6); // 1_000x $3,500
        if (draw <= 4990) return NFTClass(Class.Class12, 1_750e6); // 3_000x $1,750
        if (draw <= 9990) return NFTClass(Class.Class13, 700e6); // 5_000x $700
        if (draw <= 19990) return NFTClass(Class.Class14, 350e6); // 10_000x $350
        if (draw <= 49990) return NFTClass(Class.Class15, 175_000_000); // 30_000x $175

        return NFTClass(Class.Class16, 70e6); // 50_000x $70
    }

    function permute(
        uint256 index,
        uint256 seed
    ) public view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 6);
    }
}
