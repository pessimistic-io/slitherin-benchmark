// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IVault.sol";
import { ILoopy, ICERC20, IGlpDepositor, IRewardRouterV2, IPriceOracleProxyETH, IProtocolFeesCollector, IGlpOracleInterface, IUnitrollerInterface } from "./Interfaces.sol";

contract LoopyConstants {
  // BALANCER
  IVault internal constant BALANCER_VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
  IProtocolFeesCollector internal constant BALANCER_PROTOCOL_FEES_COLLECTOR = IProtocolFeesCollector(0xce88686553686DA562CE7Cea497CE749DA109f9F);

  // MISC TOKENS
  IERC20 internal constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
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
  IRewardRouterV2 internal constant REWARD_ROUTER_V2 =
    IRewardRouterV2(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);

  // PLUTUS
  IGlpDepositor internal constant GLP_DEPOSITOR =
    IGlpDepositor(0xEAE85745232983CF117692a1CE2ECf3d19aDA683);

  // LODESTAR
  ICERC20 internal constant lUSDC = ICERC20(0xeF25968ECC2f13b6272a37312a409D429DEF70AB);
  ICERC20 internal constant lPLVGLP = ICERC20(0xDFD276A2460eDb150DE2622f2D947EEa21C3EE48);
  IUnitrollerInterface internal constant UNITROLLER =
    IUnitrollerInterface(0xa973821E201B2C398063AC9c9B6B011D6FE5dfa3);
  IGlpOracleInterface internal constant PLVGLP_ORACLE =
    IGlpOracleInterface(0x5ba0828A5488c20a9C6521a90ecc9c49e5390604);
  IPriceOracleProxyETH internal constant PRICE_ORACLE =
    IPriceOracleProxyETH(0x569dd9Bc87c7eB5De658c912d21ccB661aA249bD);

  // no testnet contracts, so putting main for now for future use
  ICERC20 internal constant lARB = ICERC20(0xe57390EB5F0dd76B545d7349845839Ad6A4faee8);
  ICERC20 internal constant lWBTC = ICERC20(0xd917d67f9dD5fA3A193f1e076C8c636867A3571b);
  ICERC20 internal constant lUSDT = ICERC20(0x2d5a5306E6Cd7133AE576eb5eDB2128D79D11A88);
  ICERC20 internal constant lDAI = ICERC20(0x8c7B5F470251fED433e38215a959eeEFc900d995);
  ICERC20 internal constant lFRAX = ICERC20(0xc9c043A7f80258d492121d2f34e829EB6517Eb17);

  uint256 public constant DIVISOR = 1e4;
  uint16 public constant MAX_LEVERAGE = 30_000; // in {DIVISOR} terms. E.g. 30_000 = 3.0;
}
