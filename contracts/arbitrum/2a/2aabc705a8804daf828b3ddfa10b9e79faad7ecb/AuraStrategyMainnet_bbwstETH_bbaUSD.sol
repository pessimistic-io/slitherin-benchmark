//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_bbwstETH_bbaUSD is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x9fB7D6dCAC7b6aa20108BaD226c35B85A9e31B63);
    address bbwsteth = address(0x5A7f39435fD9c381e4932fa2047C9a5136A5E3E7);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address rewardPool = address(0xCA995CAab490EFb2122a046866a1ab10a9A32939);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x9fb7d6dcac7b6aa20108bad226c35b85a9e31b63000200000000000000000412,  // Balancer Pool id
      8,      // Aura Pool id
      bbwsteth   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}

