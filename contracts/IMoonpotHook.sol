// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IMoonpotHook {
    function harvestFees() external;

    function injectLiquidity(uint256 usdcAmount) external;

    function setPositionId(
        uint256 positionId,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external;

    function setCurrentFloorTick(int24 tick) external;

    function positionId() external view returns (uint256);

    function currentFloorTick() external view returns (int24);

    function getMaxSellAmount() external view returns (uint256);

    function positionTickUpper() external view returns (int24);

    function positionTickLower() external view returns (int24);

    function quoteSell(
        uint256 tmpAmount
    )
        external
        view
        returns (uint256 effectiveSell, uint256 tmpBurned, uint24 tax);

    function quoteBuy(
        uint256 usdcAmount
    ) external view returns (uint256 tmpOut, uint24 tax);
}
