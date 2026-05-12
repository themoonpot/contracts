// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockUniswapV2Factory.sol";
import "./MockUniswapV2Pair.sol";

contract MockUniswapV2Router {
    address public factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint,
        uint,
        address,
        uint
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        address pair = MockUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "Router: Pair not found");

        // 1. Transfer tokens from Manager to the Pair
        IERC20(tokenA).transferFrom(msg.sender, pair, amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountBDesired);

        // 2. Trigger the Pair to update its reserves
        liquidity = MockUniswapV2Pair(pair).mint(msg.sender);

        return (amountADesired, amountBDesired, liquidity);
    }
}
