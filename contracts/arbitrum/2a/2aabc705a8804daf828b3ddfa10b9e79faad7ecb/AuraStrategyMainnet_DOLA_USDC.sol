//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_DOLA_USDC is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8bc65Eed474D1A00555825c91FeAb6A8255C2107);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address rewardPool = address(0xAc7025Dec5E216025C76414f6ac1976227c20Ff0);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x8bc65eed474d1a00555825c91feab6a8255c2107000000000000000000000453,  // Balancer Pool id
      12,      // Aura Pool id
      underlying   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}

