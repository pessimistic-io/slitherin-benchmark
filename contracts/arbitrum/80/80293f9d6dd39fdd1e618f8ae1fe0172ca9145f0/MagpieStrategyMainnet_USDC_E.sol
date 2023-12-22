//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./MagpieStrategy.sol";

contract MagpieStrategyMainnet_USDC_E is MagpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x2977b0B54a76c2b56D32cef19f8ea83Cc766cFD9); // USDC.e LP address
    address rewardPool = address(0x1aFE333bA31E6966E33782B0D19998E89117387F); // USDC.e WombatPoolHelper
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

