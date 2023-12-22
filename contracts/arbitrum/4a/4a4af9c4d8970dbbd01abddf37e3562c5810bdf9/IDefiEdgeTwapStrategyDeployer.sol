// SPDX-License-Identifier: BSL
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./ITwapStrategyFactory.sol";
import "./ITwapStrategyManager.sol";
import "./ITwapStrategyBase.sol";
import "./IRamsesV2Pool.sol";
import "./FeedRegistryInterface.sol";

interface IDefiEdgeTwapStrategyDeployer {
    function createStrategy(
        ITwapStrategyFactory _factory,
        IRamsesV2Pool _pool,
        FeedRegistryInterface _chainlinkRegistry,
        ITwapStrategyManager _manager,
        bool[2] memory _useTwap,
        ITwapStrategyBase.Tick[] memory _ticks
    ) external returns (address);

    event StrategyDeployed(address strategy);
}

