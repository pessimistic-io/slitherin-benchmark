// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Strategy.sol";

contract StrategyFactory {
  Strategy[] public strategies;

  event Deploy(address strategyAddress);

  function createStrategy(address owner_, address usdt_, address paraswapAddress_, address tokenTransferContract_, uint16 tradePercentage_) public {
    Strategy strategy = new Strategy(owner_, usdt_, paraswapAddress_, tokenTransferContract_, tradePercentage_);
    strategies.push(strategy);

    emit Deploy(address(strategy));
  }
}
