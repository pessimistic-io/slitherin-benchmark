//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_tBTC_wETH is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xc9f52540976385A84BF416903e1Ca3983c539E34);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address rewardPool = address(0x9626E4D2b444f386fD63181f65dfEB8D141E1824);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0xc9f52540976385a84bf416903e1ca3983c539e34000200000000000000000434,  // Balancer Pool id
      3,      // Aura Pool id
      weth   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}

