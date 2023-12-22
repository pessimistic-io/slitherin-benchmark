// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./QiDaoSimpleBorrower.sol";
// import "forge-std/console.sol";

contract QiDaoSimpleBorrowerArbitrumWETH is QiDaoSimpleBorrower {
  using SafeERC20 for IERC20;

  address internal constant MAI_ADDRESS = 0x3F56e0c36d275367b8C502090EDF38289b3dEa0d;
  address internal constant VAULT_ADDRESS = 0xC76a3cBefE490Ae4450B2fCC2c38666aA99f7aa0;
  address internal constant TOKEN_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address internal constant QI_ADDRESS = 0xB9C8F0d3254007eE4b98970b94544e473Cd610EC;
  address internal constant GELATO_OPS_ADDRESS = 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;

  constructor() QiDaoSimpleBorrower(MAI_ADDRESS, VAULT_ADDRESS, TOKEN_ADDRESS, QI_ADDRESS, GELATO_OPS_ADDRESS) {
  }
}

