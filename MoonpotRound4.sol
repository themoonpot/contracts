// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./lib/TEAPermuter.sol";
import "./AbstractMoonpotRound.sol";

contract MoonpotRound4 is AbstractMoonpotRound {
    constructor(
        address _manager,
        address _usdc
    )
        AbstractMoonpotRound(
            /* Round ID */
            4,
            /* Manager Address */
            _manager,
            /* USDC Address */
            _usdc,
            /* Price */
            1.15e6,
            /* Total Tokens */
            4_000_000,
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

        // Pool: $4,000,000
        if (draw == 0) return NFTClass(Class.Class1, 400_000e6); // 1x $400,000
        if (draw <= 2) return NFTClass(Class.Class2, 200_000e6); // 2x $200,000
        if (draw <= 5) return NFTClass(Class.Class3, 100_000e6); // 3x $100,000
        if (draw <= 10) return NFTClass(Class.Class4, 40_000e6); // 5x $40,000
        if (draw <= 20) return NFTClass(Class.Class5, 20_000e6); // 10x $20,000
        if (draw <= 40) return NFTClass(Class.Class6, 10_000e6); // 20x $10,000
        if (draw <= 90) return NFTClass(Class.Class7, 4_000e6); // 50x $4,000
        if (draw <= 190) return NFTClass(Class.Class8, 2_000e6); // 100x $2,000
        if (draw <= 490) return NFTClass(Class.Class9, 1_000e6); // 300x $1,000
        if (draw <= 990) return NFTClass(Class.Class10, 400e6); // 500x $400
        if (draw <= 1990) return NFTClass(Class.Class11, 200e6); // 1,000x $200
        if (draw <= 4990) return NFTClass(Class.Class12, 100e6); // 3,000x $100
        if (draw <= 9990) return NFTClass(Class.Class13, 40e6); // 5,000x $40
        if (draw <= 19990) return NFTClass(Class.Class14, 20e6); // 10,000x $20
        if (draw <= 49990) return NFTClass(Class.Class15, 10e6); // 30,000x $10

        return NFTClass(Class.Class16, 4e6); // 50,000x $4
    }

    function permute(
        uint256 index,
        uint256 seed
    ) external view override returns (uint256) {
        return TEAPermuter.permute17(index % TOTAL_NFTS, TOTAL_NFTS, seed, 4);
    }
}
