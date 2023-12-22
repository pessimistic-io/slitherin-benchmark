// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IVault.sol";
import {ILiquidator, ICERC20, SushiRouterInterface, PriceOracleProxyETHInterface, IERC20Extended, IGLPRouter, IPlutusDepositor, IWETH, ICETH} from "./Interfaces.sol";
import "./ISwapRouter.sol";
import "./AggregatorV3Interface.sol";

contract LiquidatorConstants is ILiquidator {
    IVault internal constant BALANCER_VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IERC20 internal constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IWETH internal constant WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 internal constant PLVGLP = IERC20(0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1);
    IERC20 internal constant GLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    SushiRouterInterface FRAX_ROUTER = SushiRouterInterface(0xCAAaB0A72f781B92bA63Af27477aA46aB8F653E7);
    ISwapRouter UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    SushiRouterInterface SUSHI_ROUTER = SushiRouterInterface(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IGLPRouter GLP_ROUTER = IGLPRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    IPlutusDepositor PLUTUS_DEPOSITOR = IPlutusDepositor(0x13F0D29b5B83654A200E4540066713d50547606E);
    //placeholder address throws error otherwise
    PriceOracleProxyETHInterface PRICE_ORACLE =
        PriceOracleProxyETHInterface(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);

    AggregatorV3Interface ETHUSD_AGGREGATOR = AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);

    mapping(address => MarketData) public marketData;

    mapping(address => AggregatorV3Interface) public aggregators;
}

