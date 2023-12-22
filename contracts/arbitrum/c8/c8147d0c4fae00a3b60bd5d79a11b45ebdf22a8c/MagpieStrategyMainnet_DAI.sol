//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./MagpieStrategy.sol";

contract MagpieStrategyMainnet_DAI is MagpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x0Fa7b744F18D8E8c3D61B64b110F25CC27E73055); // DAI LP address
    address rewardPool = address(0x224c51A5FDA5bfF752F06112a7e2961Dc9A26703); // DAI WombatPoolHelper
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

