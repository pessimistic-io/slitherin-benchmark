// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IVault.sol";
import { IPloopy, ICERC20, IGlpDepositor, IRewardRouterV2, IPriceOracleProxyETH } from "./Interfaces.sol";

contract PloopyConstants {
  IVault internal constant BALANCER_VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
  IERC20 internal constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
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
  IPriceOracleProxyETH internal constant PRICE_ORACLE =
    IPriceOracleProxyETH(0x569dd9Bc87c7eB5De658c912d21ccB661aA249bD);

  uint256 public constant DIVISOR = 1e4;
  uint16 public constant MAX_LEVERAGE = 30_000; // in {DIVISOR} terms. E.g. 30_000 = 3.0;
}

