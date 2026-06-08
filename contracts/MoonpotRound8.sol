// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound8 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            8,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            1.15e6,
            /* Total Tokens */
            8_000_000,
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

        if (draw == 0) return NFTClass(Class.Class1, 800_000e6); // 1x $800,000
        if (draw <= 2) return NFTClass(Class.Class2, 400_000e6); // 2x $400,000
        if (draw <= 5) return NFTClass(Class.Class3, 200_000e6); // 3x $200,000
        if (draw <= 10) return NFTClass(Class.Class4, 80_000e6); // 5x $80,000
        if (draw <= 20) return NFTClass(Class.Class5, 40_000e6); // 10x $40,000
        if (draw <= 40) return NFTClass(Class.Class6, 20_000e6); // 20x $20,000
        if (draw <= 90) return NFTClass(Class.Class7, 8_000e6); // 50x $8,000
        if (draw <= 190) return NFTClass(Class.Class8, 4_000e6); // 100x $4,000
        if (draw <= 490) return NFTClass(Class.Class9, 2_000e6); // 300x $2,000
        if (draw <= 990) return NFTClass(Class.Class10, 800e6); // 500x $800
        if (draw <= 1990) return NFTClass(Class.Class11, 400e6); // 1_000x $400
        if (draw <= 4990) return NFTClass(Class.Class12, 200e6); // 3_000x $200
        if (draw <= 9990) return NFTClass(Class.Class13, 80e6); // 5_000x $80
        if (draw <= 19990) return NFTClass(Class.Class14, 40e6); // 10_000x $40
        if (draw <= 49990) return NFTClass(Class.Class15, 20_000_000); // 30_000x $20

        return NFTClass(Class.Class16, 8e6); // 50_000x $8
    }

    function permute(
        uint256 index,
        uint256 seed
    ) public view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 6);
    }
}
