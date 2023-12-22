//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./MagpieStrategy.sol";

contract MagpieStrategyMainnet_USDT is MagpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x85cEBD962861be410a777755dFa06914de6af003); // USDT address
    address rewardPool = address(0xBB2A70A9fF3f7b151E14bEF5052B49DB4FdFf806); // USDT WombatPoolHelper
    address wom = address(0x7B5EB3940021Ec0e8e463D5dBB4B7B09a89DDF96);
    address mgp = address(0xa61F74247455A40b01b0559ff6274441FAfa22A3);
    MagpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool
    );
    rewardTokens = [wom, mgp];
  }
}

