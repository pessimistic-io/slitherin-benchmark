//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_bbaUSD_v2 is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xc6EeE8cb7643eC2F05F46d569e9eC8EF8b41b389);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address rewardPool = address(0x237c47c7A0c4236049B872A6972Cfc0729B0D362);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0xc6eee8cb7643ec2f05f46d569e9ec8ef8b41b389000000000000000000000475,  // Balancer Pool id
      18,      // Aura Pool id
      underlying   //depositToken
    );
    rewardTokens = [aura, bal, arb];
  }
}

