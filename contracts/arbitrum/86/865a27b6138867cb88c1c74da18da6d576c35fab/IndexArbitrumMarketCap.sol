// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";

import { IndexArbitrum } from "./IndexArbitrum.sol";
import { IChainlinkAggregatorV3 } from "./IChainlinkAggregatorV3.sol";
import { Constants } from "./Constants.sol";
import { Errors } from "./Errors.sol";
import { SwapAdapter } from "./SwapAdapter.sol";

contract IndexArbitrumMarketCap is UUPSUpgradeable, IndexArbitrum {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IndexStrategyInitParams calldata initParams)
        external
        initializer
    {
        __UUPSUpgradeable_init();
        __IndexStrategyUpgradeable_init(initParams);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

