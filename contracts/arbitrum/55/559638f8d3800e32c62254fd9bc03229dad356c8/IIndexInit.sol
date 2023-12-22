// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IChainlinkAggregatorV3 } from "./IChainlinkAggregatorV3.sol";
import { SwapAdapter } from "./SwapAdapter.sol";
import { IIndexStrategy } from "./IIndexStrategy.sol";

interface IIndexInit {
    struct IndexStrategyInitParams {
        address wNATIVE;
        address indexToken;
        Component[] components;
        SwapRoute[] swapRoutes;
        address[] whitelistedTokens;
        address oracle;
        uint256 equityValuationLimit;
    }

    struct Component {
        address token;
        uint256 weight;
    }

    struct SwapRoute {
        address token0;
        address token1;
        address router;
        SwapAdapter.DEX dex;
        SwapAdapter.PairData pairData;
    }
}

