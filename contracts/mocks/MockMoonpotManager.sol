// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "../MoonpotManager.sol";

/// @dev Test-only manager. Identical logic to {MoonpotManager} (inherited, not
/// re-implemented); only the contract name differs so a mock deploy is
/// unmistakable on explorers. Not for production.
contract MockMoonpotManager is MoonpotManager {
    constructor(
        address _usdc,
        address _tmp,
        address _nft,
        address _comp,
        address _vrf,
        bytes32 _key,
        uint256 _sub,
        address _poolm,
        address _posm,
        address _permit2,
        address _hook
    )
        MoonpotManager(
            _usdc,
            _tmp,
            _nft,
            _comp,
            _vrf,
            _key,
            _sub,
            _poolm,
            _posm,
            _permit2,
            _hook
        )
    {}
}
