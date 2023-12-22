// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IVault.sol";
import {ILoopy, ICERC20, IGlpDepositor, IRewardRouterV2, IPriceOracleProxyETH, IProtocolFeesCollector, IGlpOracleInterface, IUnitrollerInterface, SushiRouterInterface} from "./Interfaces.sol";
import "./ISwapRouter.sol";

contract LoopyConstants {
    // BALANCER
    IVault internal constant BALANCER_VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IProtocolFeesCollector internal constant BALANCER_PROTOCOL_FEES_COLLECTOR =
        IProtocolFeesCollector(0xce88686553686DA562CE7Cea497CE749DA109f9F);

    // UNDERLYING TOKENS
    IERC20 internal constant USDC_BRIDGED = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 internal constant USDC_NATIVE = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    IERC20 internal constant ARB = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
    IERC20 internal constant WBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20 internal constant USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 internal constant DAI = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    IERC20 internal constant FRAX = IERC20(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
    IERC20 internal constant PLVGLP = IERC20(0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1);
    IERC20 internal constant GLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);

    // GMX
    IERC20 internal constant VAULT = IERC20(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    IERC20 internal constant GLP_MANAGER = IERC20(0x3963FfC9dff443c2A94f21b129D429891E32ec18);
    IERC20 internal constant sGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);
    IRewardRouterV2 internal constant REWARD_ROUTER_V2 = IRewardRouterV2(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);

    // PLUTUS
    IGlpDepositor internal constant GLP_DEPOSITOR = IGlpDepositor(0xEAE85745232983CF117692a1CE2ECf3d19aDA683);

    // LODESTAR
    ICERC20 internal constant lUSDCe = ICERC20(0x1ca530f02DD0487cef4943c674342c5aEa08922F);
    ICERC20 internal constant lUSDC = ICERC20(0x4C9aAed3b8c443b4b634D1A189a5e25C604768dE);
    ICERC20 internal constant lPLVGLP = ICERC20(0xeA0a73c17323d1a9457D722F10E7baB22dc0cB83);
    ICERC20 internal constant lARB = ICERC20(0x8991d64fe388fA79A4f7Aa7826E8dA09F0c3C96a);
    ICERC20 internal constant lWBTC = ICERC20(0xC37896BF3EE5a2c62Cdbd674035069776f721668);
    ICERC20 internal constant lUSDT = ICERC20(0x9365181A7df82a1cC578eAE443EFd89f00dbb643);
    ICERC20 internal constant lDAI = ICERC20(0x4987782da9a63bC3ABace48648B15546D821c720);
    ICERC20 internal constant lFRAX = ICERC20(0xD12d43Cdf498e377D3bfa2c6217f05B466E14228);

    IUnitrollerInterface internal constant UNITROLLER =
        IUnitrollerInterface(0xa86DD95c210dd186Fa7639F93E4177E97d057576);
    IGlpOracleInterface internal constant PLVGLP_ORACLE =
        IGlpOracleInterface(0x5ba0828A5488c20a9C6521a90ecc9c49e5390604);
    IPriceOracleProxyETH internal constant PRICE_ORACLE =
        IPriceOracleProxyETH(0xcCf9393df2F656262FD79599175950faB4D4ec01);

    // SWAP
    ISwapRouter internal constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    SushiRouterInterface internal constant SUSHI_ROUTER =
        SushiRouterInterface(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    uint256 public constant DIVISOR = 1e4;
    uint16 public constant MAX_LEVERAGE = 30_000; // in {DIVISOR} terms. E.g. 30_000 = 3.0;

    // set default fee percentage (can be updated via admin function below)
    uint256 public protocolFeePercentage = 25; // 25 basis points
}
