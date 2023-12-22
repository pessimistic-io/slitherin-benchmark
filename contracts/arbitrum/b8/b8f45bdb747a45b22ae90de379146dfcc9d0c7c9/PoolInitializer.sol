// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "./IRamsesV2Factory.sol";
import "./IRamsesV2Pool.sol";

import "./PeripheryUpgradeable.sol";
import "./IPoolInitializer.sol";

/// @title Creates and initializes V3 Pools
abstract contract PoolInitializer is IPoolInitializer, PeripheryUpgradeable {
    /// @inheritdoc IPoolInitializer
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable override returns (address pool) {
        require(token0 < token1);
        pool = IRamsesV2Factory(factory).getPool(token0, token1, fee);

        if (pool == address(0)) {
            pool = IRamsesV2Factory(factory).createPool(token0, token1, fee);
            IRamsesV2Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing, , , , , , ) = IRamsesV2Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IRamsesV2Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }
}

