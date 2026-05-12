// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MockUniswapV2Pair.sol";

contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair) {
        require(getPair[tokenA][tokenB] == address(0), "PAIR_EXISTS");
        MockUniswapV2Pair newPair = new MockUniswapV2Pair(tokenA, tokenB);
        pair = address(newPair);
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair; // Populate reverse mapping
    }
}
