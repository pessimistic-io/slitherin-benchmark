// SPDX-License-Identifier: BSL
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IStrategyFactory.sol";
import "./IStrategyManager.sol";
import "./IStrategyBase.sol";
import "./FeedRegistryInterface.sol";

interface IDefiEdgeStrategyDeployer {
    function createStrategy(
        IStrategyFactory _factory,
        IAlgebraPool _pool,
        FeedRegistryInterface _chainlinkRegistry,
        IStrategyManager _manager,
        bool[2] memory _usdAsBase,
        IStrategyBase.Tick[] memory _ticks
    ) external returns (address);

    event StrategyDeployed(address strategy);
}

