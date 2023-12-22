//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategy.sol";

contract BalancerStrategyMainnet_rETH_aWETH is BalancerStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xCba9Ff45cfB9cE238AfDE32b0148Eb82CbE63562);
    address bbaweth = address(0xDa1CD1711743e57Dd57102E9e61b75f3587703da);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address gauge = address(0x6c34d77a57226f9Df6eC476B20913350832eBfEC);
    BalancerStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0xcba9ff45cfb9ce238afde32b0148eb82cbe635620000000000000000000003fd,  // Pool id
      bbaweth,   //depositToken
      true      //boosted
    );
    rewardTokens = [bal];
    reward2WETH[bal] = [bal, weth];
    WETH2deposit = [weth, bbaweth];
    poolIds[bal][weth] = 0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001;
    poolIds[weth][bbaweth] = 0xda1cd1711743e57dd57102e9e61b75f3587703da0000000000000000000003fc;
  }
}

