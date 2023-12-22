// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

/// @title Addresses for Arbitrum
/// @author Buooy
/// @dev Defines the core addresses in the arbitrum network
library Addresses {
  // ERC20 Tokens
  address public constant AUSDC_ADDRESS = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
  address public constant ESGMX_ADDRESS = 0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;
  address public constant GLP_ADDRESS = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
  address public constant GLP_SUPPLY_ADDRESS = 0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258;
  address public constant GMX_ADDRESS = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
  address public constant WBTC_ADDRESS = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  address public constant WBTC_DEBT_VARIABLE_ADDRESS = 0x92b42c66840C7AD907b4BF74879FF3eF7c529473;
  address public constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public constant WETH_DEBT_VARIABLE_ADDRESS = 0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351;
  address public constant USDC_ADDRESS = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

  // Protocols
  address public constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
  address public constant GLP_REWARD_TRACKER = 0x4e971a87900b931fF39d1Aad67697F49835400b6;
  address public constant GMX_REWARD_ROUTER_V1 = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
  address public constant GMX_REWARD_ROUTER_V2 = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
  address public constant GMX_READER = 0x22199a49A999c351eF7927602CFB187ec3cae489;
  address public constant GMX_ROUTER = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
  address public constant GMX_VAULT = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
  address public constant GLP_MANAGER = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
}
