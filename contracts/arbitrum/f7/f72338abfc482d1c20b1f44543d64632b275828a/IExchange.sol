// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct Purchase {
    uint256 usdcAmount;
    uint256 tokenAmount;
}

enum TradeType { Buy, Sell }

interface IExchange {
  function buy(uint256 usdcAmount) external returns (Purchase memory);
  function sell(uint256 usdcAmount) external returns (Purchase memory);
}


