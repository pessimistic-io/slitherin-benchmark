//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategy.sol";

contract BalancerStrategyMainnet_bbaUSD is BalancerStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xEE02583596AEE94ccCB7e8ccd3921d955f17982A);
    address bbausdc = address(0x7c82A23B4C48D796dee36A9cA215b641C6a8709d);
    address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address gauge = address(0xb0Bdd5000307144Ed7d30Cf4025Ec1FBA9D79D65);
    BalancerStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0xee02583596aee94cccb7e8ccd3921d955f17982a00000000000000000000040a,  // Pool id
      bbausdc,   //depositToken
      true      //boosted
    );
    rewardTokens = [bal];
    reward2WETH[bal] = [bal, weth];
    WETH2deposit = [weth, usdc, bbausdc];
    poolIds[bal][weth] = 0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001;
    poolIds[usdc][bbausdc] = 0x7c82a23b4c48d796dee36a9ca215b641c6a8709d000000000000000000000406;
    router[weth][usdc] = camelotRouter;
  }
}

