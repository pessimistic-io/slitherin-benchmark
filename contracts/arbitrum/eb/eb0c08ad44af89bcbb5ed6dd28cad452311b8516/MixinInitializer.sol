// SPDX-License-Identifier: Apache 2.0
pragma solidity >=0.8.0 <0.9.0;

import "./MixinImmutables.sol";
import "./MixinStorage.sol";
import "./IERC20.sol";
import "./IRigoblockPoolProxyFactory.sol";

abstract contract MixinInitializer is MixinImmutables, MixinStorage {
    modifier onlyUninitialized() {
        // pool proxy is always initialized in the constructor, therefore
        // empty extcodesize means the pool has not been initialized
        address self = address(this);
        uint256 size;
        assembly {
            size := extcodesize(self)
        }
        require(size == 0, "POOL_ALREADY_INITIALIZED_ERROR");
        _;
    }

    /// @inheritdoc IRigoblockV3PoolInitializer
    function initializePool() external override onlyUninitialized {
        uint8 tokenDecimals = 18;
        IRigoblockPoolProxyFactory.Parameters memory initParams = IRigoblockPoolProxyFactory(msg.sender).parameters();

        if (initParams.baseToken != address(0)) {
            tokenDecimals = IERC20(initParams.baseToken).decimals();
        }

        // a pool with small decimals could easily underflow.
        assert(tokenDecimals >= 6);

        poolWrapper().pool = Pool({
            name: initParams.name,
            symbol: initParams.symbol,
            decimals: tokenDecimals,
            owner: initParams.owner,
            unlocked: true,
            baseToken: initParams.baseToken
        });

        emit PoolInitialized(msg.sender, initParams.owner, initParams.baseToken, initParams.name, initParams.symbol);
    }
}

