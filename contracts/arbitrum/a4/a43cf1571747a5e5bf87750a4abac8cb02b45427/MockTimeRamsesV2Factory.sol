// SPDX-License-Identifier: GPL-2.0-or-later-1.1
pragma solidity =0.7.6;

import "./RamsesV2Factory.sol";
import "./MockTimeRamsesV2Pool.sol";

/// @title Canonical Ramses V2 factory
/// @notice Deploys Ramses V2 pools and manages ownership and control over pool protocol fees
contract MockTimeRamsesV2Factory is RamsesV2Factory {
    /// @dev only for testing, can create pools with no restriction to tick spacing
    /// doesn't check if the same fee tier exists
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickSpacing
    ) external returns (address pool) {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        pool = _deployWithTickSpacing(
            address(this),
            nfpManager,
            veRam,
            voter,
            token0,
            token1,
            fee,
            tickSpacing
        );
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    function _deployWithTickSpacing(
        address factory,
        address nfpManager,
        address veRam,
        address voter,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing
    ) internal returns (address pool) {
        pool = address(
            new RamsesBeaconProxy{
                salt: keccak256(abi.encode(token0, token1, fee, tickSpacing))
            }()
        );
        IRamsesV2Pool(pool).initialize(
            factory,
            nfpManager,
            veRam,
            voter,
            token0,
            token1,
            fee,
            tickSpacing
        );

        MockTimeRamsesV2Pool(pool).initializeTime();
    }
}

