// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;

import {NotionalProxy} from "./NotionalProxy.sol";
import {IWstETH} from "./IWstETH.sol";
import {IBalancerVault, IAsset} from "./IBalancerVault.sol";
import {WETH9} from "./WETH9.sol";
import {ISwapRouter as UniV3ISwapRouter} from "./ISwapRouter.sol";
import {IUniV2Router2} from "./IUniV2Router2.sol";
import {ICurveRouter} from "./ICurveRouter.sol";
import {ICurveRegistry} from "./ICurveRegistry.sol";
import {ICurveRouterV2} from "./ICurveRouterV2.sol";

/// @title Hardcoded Deployment Addresses for ETH Mainnet
library Deployments {
    NotionalProxy internal constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    IWstETH internal constant WRAPPED_STETH = IWstETH(0x5979D7b546E38E414F7E9822514be443A4800529);
    address internal constant ETH_ADDRESS = address(0);
    WETH9 internal constant WETH =
        WETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    UniV3ISwapRouter internal constant UNIV3_ROUTER = UniV3ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address internal constant ZERO_EX = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    IUniV2Router2 internal constant UNIV2_ROUTER = IUniV2Router2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address internal constant ALT_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // For CurveAdapter
    ICurveRegistry public constant CURVE_REGISTRY = ICurveRegistry(0x90E00ACe148ca3b23Ac1bC8C240C2a7Dd9c2d7f5);
    ICurveRouter public constant CURVE_ROUTER = ICurveRouter(0xfA9a30350048B2BF66865ee20363067c66f67e58);

    // For CurveV2Adapter
    ICurveRouterV2 public constant CURVE_ROUTER_V2 = ICurveRouterV2(0x4c2Af2Df2a7E567B5155879720619EA06C5BB15D);
}

