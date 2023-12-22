// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./QiDaoSimpleBorrower.sol";
// import "forge-std/console.sol";

contract QiDaoSimpleBorrowerArbitrumWBTC is QiDaoSimpleBorrower {
  using SafeERC20 for IERC20;

  address internal constant MAI_ADDRESS = 0x3F56e0c36d275367b8C502090EDF38289b3dEa0d;
  address internal constant VAULT_ADDRESS = 0xB237f4264938f0903F5EC120BB1Aa4beE3562FfF;
  address internal constant TOKEN_ADDRESS = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  address internal constant QI_ADDRESS = 0xB9C8F0d3254007eE4b98970b94544e473Cd610EC;
  address internal constant GELATO_OPS_ADDRESS = 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;

  constructor() QiDaoSimpleBorrower(MAI_ADDRESS, VAULT_ADDRESS, TOKEN_ADDRESS, QI_ADDRESS, GELATO_OPS_ADDRESS) {
  }
}

