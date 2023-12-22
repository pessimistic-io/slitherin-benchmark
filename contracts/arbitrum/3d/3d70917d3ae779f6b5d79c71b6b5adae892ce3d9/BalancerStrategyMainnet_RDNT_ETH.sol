//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategy.sol";

contract BalancerStrategyMainnet_RDNT_ETH is BalancerStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address gauge = address(0xcf9f895296F5e1D66a7D4dcf1d92e1B435E9f999);
    BalancerStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0x32df62dc3aed2cd6224193052ce665dc181658410002000000000000000003bd,  // Pool id
      weth,   //depositToken
      false      //boosted
    );
    rewardTokens = [bal];
    reward2WETH[bal] = [bal, weth];
    poolIds[bal][weth] = 0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001;
  }
}

