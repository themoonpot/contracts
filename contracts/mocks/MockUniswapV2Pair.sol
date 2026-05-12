// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUniswapV2Pair {
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _t0, address _t1) {
        token0 = _t0;
        token1 = _t1;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    /**
     * @dev In real Uniswap, mint() is called AFTER tokens are transferred.
     * It updates reserves to match the current balances.
     */
    function mint(address) external returns (uint liquidity) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);

        emit Sync(reserve0, reserve1);

        // Return a dummy liquidity value
        return 1000;
    }
}
