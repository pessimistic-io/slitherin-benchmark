//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_wstETH_wETH is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x36bf227d6BaC96e2aB1EbB5492ECec69C691943f);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address rewardPool = address(0x49e998899FF11598182918098588E8b90d7f60D3);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x36bf227d6bac96e2ab1ebb5492ecec69c691943f000200000000000000000316,  // Balancer Pool id
      0,      // Aura Pool id
      weth   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}

