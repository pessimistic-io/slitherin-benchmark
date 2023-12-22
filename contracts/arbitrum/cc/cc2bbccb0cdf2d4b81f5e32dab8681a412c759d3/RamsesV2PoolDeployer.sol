// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import "./IRamsesV2PoolDeployer.sol";

import "./IRamsesV2Pool.sol";

import "./IBeacon.sol";
import "./BeaconProxy.sol";

contract RamsesV2PoolDeployer is IRamsesV2PoolDeployer, IBeacon {
    struct Parameters {
        address factory;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
    }

    /// @inheritdoc IRamsesV2PoolDeployer
    Parameters public override parameters;

    /// @inheritdoc IBeacon
    address public override implementation;

    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    /// @param factory The contract address of the Ramses V2 factory
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The spacing between usable ticks
    function deploy(
        address factory,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing
    ) internal returns (address pool) {
        parameters = Parameters({
            factory: factory,
            token0: token0,
            token1: token1,
            fee: fee,
            tickSpacing: tickSpacing
        });
        pool = address(
            new BeaconProxy{salt: keccak256(abi.encode(token0, token1, fee))}(
                address(this),
                ""
            )
        );
        IRamsesV2Pool(pool).initialize();

        delete parameters;
    }
}

