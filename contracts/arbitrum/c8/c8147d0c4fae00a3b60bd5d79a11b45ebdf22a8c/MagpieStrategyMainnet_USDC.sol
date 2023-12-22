//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./MagpieStrategy.sol";

contract MagpieStrategyMainnet_USDC is MagpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xE5232c2837204ee66952f365f104C09140FB2E43); // USDC LP address
    address rewardPool = address(0x58BB9749e35E15Ca016AD624EfB5297826310ea1); // USDC WombatPoolHelper
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

