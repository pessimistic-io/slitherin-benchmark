//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategy.sol";

contract BalancerStrategyMainnet_tBTC_wBTC is BalancerStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x542F16DA0efB162D20bF4358EfA095B70A100f9E);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address tbtc = address(0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40);
    address gauge = address(0xb438c6cc53315FfA3fcD1bc8b27d6c3155b0B56A);
    BalancerStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0x542f16da0efb162d20bf4358efa095b70a100f9e000000000000000000000436,  // Pool id
      tbtc,   //depositToken
      true      //boosted
    );
    rewardTokens = [bal];
    reward2WETH[bal] = [bal, weth];
    WETH2deposit = [weth, tbtc];
    poolIds[bal][weth] = 0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001;
    poolIds[weth][tbtc] = 0xc9f52540976385a84bf416903e1ca3983c539e34000200000000000000000434;
  }
}

