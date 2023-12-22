//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_auraBAL_wstETH is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xc7FA3A3527435720f0e2a4c1378335324dd4F9b3);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address wsteth = address(0x5979D7b546E38E414F7E9822514be443A4800529);
    address rewardPool = address(0x1597010ffE2e25a584D9705C1e48585BbfE56fC0);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0xc7fa3a3527435720f0e2a4c1378335324dd4f9b3000200000000000000000459,  // Balancer Pool id
      9,      // Aura Pool id
      wsteth   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}

