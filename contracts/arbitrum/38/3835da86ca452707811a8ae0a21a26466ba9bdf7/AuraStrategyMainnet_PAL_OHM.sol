//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_PAL_OHM is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8d333f82e0693f53fA48c40d5D4547142E907e1D);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address ohm = address(0xf0cb2dc0db5e6c66B9a70Ac27B06b878da017028);
    address rewardPool = address(0x9fC8196aAdCd24a5ea90e65d975Ef3332D7435db);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x8d333f82e0693f53fa48c40d5d4547142e907e1d000200000000000000000437,  // Balancer Pool id
      11,      // Aura Pool id
      ohm   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}

