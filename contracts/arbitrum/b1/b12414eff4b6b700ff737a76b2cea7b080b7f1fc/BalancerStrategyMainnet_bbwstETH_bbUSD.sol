//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategy.sol";

contract BalancerStrategyMainnet_bbwstETH_bbUSD is BalancerStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x9fB7D6dCAC7b6aa20108BaD226c35B85A9e31B63);
    address bbwsteth = address(0x5A7f39435fD9c381e4932fa2047C9a5136A5E3E7);
    address bbaweth = address(0xDa1CD1711743e57Dd57102E9e61b75f3587703da);
    address wsteth = address(0x5979D7b546E38E414F7E9822514be443A4800529);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address ldo = address(0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60);
    address gauge = address(0xc01F38a0557C53d3b0427F644998d1F76972ecA1);
    BalancerStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0x9fb7d6dcac7b6aa20108bad226c35b85a9e31b63000200000000000000000412,  // Pool id
      bbwsteth,   //depositToken
      false      //boosted
    );
    rewardTokens = [bal, ldo];
    reward2WETH[bal] = [bal, weth];
    reward2WETH[ldo] = [ldo, wsteth, weth];
    WETH2deposit = [weth, bbaweth, bbwsteth];
    poolIds[bal][weth] = 0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001;
    poolIds[wsteth][weth] = 0xfb5e6d0c1dfed2ba000fbc040ab8df3615ac329c000000000000000000000159;
    poolIds[weth][bbaweth] = 0xda1cd1711743e57dd57102e9e61b75f3587703da0000000000000000000003fc;
    poolIds[bbaweth][bbwsteth] = 0x5a7f39435fd9c381e4932fa2047c9a5136a5e3e7000000000000000000000400;
    router[ldo][wsteth] = camelotRouter;
  }
}

