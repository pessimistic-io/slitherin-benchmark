//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_rETH_aWETH is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xCba9Ff45cfB9cE238AfDE32b0148Eb82CbE63562);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address rewardPool = address(0x0DCb3664BaFe8f7Afb2174C1FF736fe9011De9ff);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0xcba9ff45cfb9ce238afde32b0148eb82cbe635620000000000000000000003fd,  // Balancer Pool id
      4,      // Aura Pool id
      underlying   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}

