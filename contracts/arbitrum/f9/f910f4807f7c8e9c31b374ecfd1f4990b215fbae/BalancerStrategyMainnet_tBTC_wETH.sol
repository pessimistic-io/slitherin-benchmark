//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategy.sol";

contract BalancerStrategyMainnet_tBTC_wETH is BalancerStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xc9f52540976385A84BF416903e1Ca3983c539E34);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address gauge = address(0x011417BBED6FC9cefF36C032D431b0eFcBA7f8B3);
    BalancerStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0xc9f52540976385a84bf416903e1ca3983c539e34000200000000000000000434,  // Pool id
      weth,   //depositToken
      false      //boosted
    );
    rewardTokens = [bal];
    reward2WETH[bal] = [bal, weth];
    poolIds[bal][weth] = 0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001;
  }
}

