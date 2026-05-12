// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice Minimal swap helper for fork tests against the real v4 PoolManager.
/// Pre-approve the router for both currencies before calling `swap`.
contract ForkRouter is IUnlockCallback {
    IPoolManager public immutable poolManager;

    struct CallbackData {
        address sender;
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

    error NotPoolManager();

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function swap(
        PoolKey memory key,
        SwapParams memory params,
        bytes memory hookData
    ) external returns (BalanceDelta delta) {
        delta = abi.decode(
            poolManager.unlock(abi.encode(CallbackData(msg.sender, key, params, hookData))),
            (BalanceDelta)
        );
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();

        CallbackData memory cb = abi.decode(data, (CallbackData));
        BalanceDelta delta = poolManager.swap(cb.key, cb.params, cb.hookData);

        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();

        if (d0 < 0) _settle(cb.key.currency0, cb.sender, uint128(-d0));
        else if (d0 > 0) poolManager.take(cb.key.currency0, cb.sender, uint128(d0));

        if (d1 < 0) _settle(cb.key.currency1, cb.sender, uint128(-d1));
        else if (d1 > 0) poolManager.take(cb.key.currency1, cb.sender, uint128(d1));

        return abi.encode(delta);
    }

    function _settle(Currency currency, address payer, uint256 amount) internal {
        poolManager.sync(currency);
        IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(poolManager), amount);
        poolManager.settle();
    }
}
