// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// const
uint256 constant BP = 10000; //100%
uint128 constant MINT_PRICE = 0.01 ether;
uint256 constant MINTER_POWER_0 = 10;
uint256 constant MINTER_POWER_INCREASE = 100;
uint256 constant WORTH_INCREASE_BP = 1000; //10%
uint256 constant TIMES = 1e12;
uint256 constant POWER_TO_SO3 = 200;

error INVALID_MINT_PRICE();
error DISABLE_BUY_SELF();
error MINSER_IS_NOT_IN_LIST();
error MINNER_EXIST();
error MINNER_NOT_EXIST();
error ETH_TRANSFER_FAILED();
error INVALID_BUY_PRICE();
error INVALID_BUYER();
error INVALID_WORTH();
error CAST_TO_128_OVERFLOW();
error WITHDRAW_INSUFFICIENT_BALANCE();
error INVALID_CHEF_AGENT();
error ADDRESS_IS_EMPTY();
error HOST_MISMATCH();
error UNAUTHORIZED();
error TRADE_NOT_STARTED();

