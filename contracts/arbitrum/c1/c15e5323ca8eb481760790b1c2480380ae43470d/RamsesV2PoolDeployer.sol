// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "./IRamsesV2PoolDeployer.sol";
import "./IRamsesV2Pool.sol";

import "./RamsesBeaconProxy.sol";

import "./IBeacon.sol";

contract RamsesV2PoolDeployer is IRamsesV2PoolDeployer, IBeacon {
    /// @inheritdoc IBeacon
    address public override implementation;

    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    /// @param factory The contract address of the Ramses V2 factory
    /// @param nfpManager The contract address of the Ramses V2 NFP Manager
    /// @param veRam The contract address of the Ramses Voting Escrow
    /// @param voter The contract address of the Ramses Voter
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The spacing between usable ticks
    function _deploy(
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
                salt: keccak256(abi.encode(token0, token1, fee))
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
    }
}

