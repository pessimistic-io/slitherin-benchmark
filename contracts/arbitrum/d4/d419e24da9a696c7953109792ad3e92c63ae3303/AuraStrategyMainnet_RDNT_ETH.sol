//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_RDNT_ETH is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address rewardPool = address(0xa17492d89cB2D0bE1dDbd0008F8585EDc5B0ACf3);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0x32df62dc3aed2cd6224193052ce665dc181658410002000000000000000003bd,  // Balancer Pool id
      1,      // Aura Pool id
      weth   //depositToken
    );
    rewardTokens = [aura, bal];
  }
}

