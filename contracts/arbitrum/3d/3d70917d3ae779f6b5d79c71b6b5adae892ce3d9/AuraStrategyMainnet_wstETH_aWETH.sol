//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_wstETH_aWETH is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x5A7f39435fD9c381e4932fa2047C9a5136A5E3E7);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address rewardPool = address(0x2a288e87A044eA6a73a19178EC11903c4DF68f17);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x5a7f39435fd9c381e4932fa2047c9a5136a5e3e7000000000000000000000400,  // Balancer Pool id
      7,      // Aura Pool id
      underlying   //depositToken
    );
    rewardTokens = [aura, bal, arb];
  }
}

