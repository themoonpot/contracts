// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound24 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            24,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            1.70e6,
            /* Total Tokens */
            600_000_000,
            /* Total NFTs */
            99_991,
            /* Share Community */
            1.00e6,
            /* Share Company */
            0.10e6,
            /* Share Liquidity */
            0.60e6
        )
    {}

    function getNFTClass(
        uint32 draw
    ) public view override returns (NFTClass memory) {
        if (draw >= TOTAL_NFTS) return NFTClass(Class.None, 0);

        if (draw == 0) return NFTClass(Class.Class1, 60_000_000e6); // 1x $60,000,000
        if (draw <= 2) return NFTClass(Class.Class2, 30_000_000e6); // 2x $30,000,000
        if (draw <= 5) return NFTClass(Class.Class3, 15_000_000e6); // 3x $15,000,000
        if (draw <= 10) return NFTClass(Class.Class4, 6_000_000e6); // 5x $6,000,000
        if (draw <= 20) return NFTClass(Class.Class5, 3_000_000e6); // 10x $3,000,000
        if (draw <= 40) return NFTClass(Class.Class6, 1_500_000e6); // 20x $1,500,000
        if (draw <= 90) return NFTClass(Class.Class7, 600_000e6); // 50x $600,000
        if (draw <= 190) return NFTClass(Class.Class8, 300_000e6); // 100x $300,000
        if (draw <= 490) return NFTClass(Class.Class9, 150_000e6); // 300x $150,000
        if (draw <= 990) return NFTClass(Class.Class10, 60_000e6); // 500x $60,000
        if (draw <= 1990) return NFTClass(Class.Class11, 30_000e6); // 1_000x $30,000
        if (draw <= 4990) return NFTClass(Class.Class12, 15_000e6); // 3_000x $15,000
        if (draw <= 9990) return NFTClass(Class.Class13, 6_000e6); // 5_000x $6,000
        if (draw <= 19990) return NFTClass(Class.Class14, 3_000e6); // 10_000x $3,000
        if (draw <= 49990) return NFTClass(Class.Class15, 1_500_000_000); // 30_000x $1,500

        return NFTClass(Class.Class16, 600e6); // 50_000x $600
    }

    function permute(
        uint256 index,
        uint256 seed
    ) public view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 6);
    }
}
