// SPDX-License-Identifier: BUSDL-1.1
pragma solidity 0.6.11;

import {IERC20, INameIdentifier} from "./common_Imports.sol";
import {     ILiquidityGauge } from "./interfaces_Imports.sol";
import {IMetaPool} from "./interfaces_Imports.sol";

abstract contract CurveUstWormholeConstants is INameIdentifier {
    string public constant override NAME = "curve-ust-wormhole";

    // sometimes a metapool is its own LP token; otherwise,
    // you can obtain from `token` attribute
    IERC20 public constant LP_TOKEN =
        IERC20(0xCEAF7747579696A2F0bb206a14210e3c9e6fB269);

    // metapool primary underlyer
    IERC20 public constant PRIMARY_UNDERLYER =
        IERC20(0xa693B19d2931d498c5B318dF961919BB4aee87a5);

    IMetaPool public constant META_POOL =
        IMetaPool(0xCEAF7747579696A2F0bb206a14210e3c9e6fB269);

    ILiquidityGauge public constant LIQUIDITY_GAUGE =
        ILiquidityGauge(0xb0f5d00e5916c8b8981e99191A1458704B587b2b);
}

