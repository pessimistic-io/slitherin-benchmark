//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_bbaUSD is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xEE02583596AEE94ccCB7e8ccd3921d955f17982A);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address rewardPool = address(0x4fA10A40407BA386E3A863381200b4e6049950fa);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0xee02583596aee94cccb7e8ccd3921d955f17982a00000000000000000000040a,  // Balancer Pool id
      2,      // Aura Pool id
      underlying   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}

