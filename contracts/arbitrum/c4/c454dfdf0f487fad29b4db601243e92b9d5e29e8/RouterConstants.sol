// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ICERC20, SushiRouterInterface, PriceOracleProxyETHInterface, IERC20Extended, IGLPRouter, IPlutusDepositor, IWETH, ICETH} from "./Interfaces.sol";
import "./ISwapRouter.sol";
import "./AggregatorV3Interface.sol";
import "./IERC20.sol";

contract RouterConstants {
    uint256 constant BASE = 1e18;
    mapping(address => uint256) public PreviousReserves;

    address internal constant lETH = 0x3F491B62f7E1A3634C3b4ef4A441371D31f8Dc77;
    IERC20 internal constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IWETH internal constant WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 internal constant PLVGLP = IERC20(0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1);
    IERC20 internal constant GLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    IERC20 internal constant SGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);
    SushiRouterInterface internal constant FRAX_ROUTER =
        SushiRouterInterface(0xCAAaB0A72f781B92bA63Af27477aA46aB8F653E7);
    ISwapRouter internal constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    SushiRouterInterface internal constant SUSHI_ROUTER =
        SushiRouterInterface(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IGLPRouter internal constant GLP_ROUTER = IGLPRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    IPlutusDepositor internal constant PLUTUS_DEPOSITOR = IPlutusDepositor(0xEAE85745232983CF117692a1CE2ECf3d19aDA683);
    //placeholder address throws error otherwise
    PriceOracleProxyETHInterface internal constant PRICE_ORACLE =
        PriceOracleProxyETHInterface(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);

    AggregatorV3Interface internal constant ETHUSD_AGGREGATOR =
        AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
    AggregatorV3Interface internal constant SEQUENCER =
        AggregatorV3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);
    uint256 internal constant GRACE_PERIOD_TIME = 3600;

    mapping(address => AggregatorV3Interface) public aggregators;
}

