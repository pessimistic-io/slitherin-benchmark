//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_wstETH_aWETH_v2 is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x45C4D1376943Ab28802B995aCfFC04903Eb5223f);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address rewardPool = address(0x10dCf485EA947faf9A9B819A2d3207323d0c72Ca);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x45c4d1376943ab28802b995acffc04903eb5223f000000000000000000000470,  // Balancer Pool id
      17,      // Aura Pool id
      underlying   //depositToken
    );
    rewardTokens = [aura, bal, arb];
  }
}

