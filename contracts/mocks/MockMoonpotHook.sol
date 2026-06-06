// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import "../MoonpotHook.sol";

/// @dev Test-only hook. Identical logic to {MoonpotHook} (inherited, not
/// re-implemented); only the contract name differs. Still must be deployed at a
/// CREATE2-mined address carrying the same v4 permission flags. Not for
/// production.
contract MockMoonpotHook is MoonpotHook {
    constructor(
        IPoolManager _poolManager,
        address _posm,
        address _permit2,
        address _usdc,
        address _tmp,
        address _owner
    ) MoonpotHook(_poolManager, _posm, _permit2, _usdc, _tmp, _owner) {}
}
