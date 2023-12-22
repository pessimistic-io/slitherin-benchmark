// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import "./RamsesV2PoolDeployer.sol";

contract MockTimeRamsesV2PoolDeployer is RamsesV2PoolDeployer {
    function deploy(
        address factory,
        address nfpManager,
        address veRam,
        address voter,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing
    ) external returns (address pool) {
        return
            _deploy(
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

