//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategy.sol";

contract BalancerStrategyMainnet_wstETH_aWETH is BalancerStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x5A7f39435fD9c381e4932fa2047C9a5136A5E3E7);
    address bbaweth = address(0xDa1CD1711743e57Dd57102E9e61b75f3587703da);
    address wsteth = address(0x5979D7b546E38E414F7E9822514be443A4800529);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address ldo = address(0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60);
    address gauge = address(0xae9F2cE52FE89DD78e6F13d5d7b33125aE3dFF8C);
    BalancerStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0x5a7f39435fd9c381e4932fa2047c9a5136a5e3e7000000000000000000000400,  // Pool id
      bbaweth,   //depositToken
      true      //boosted
    );
    rewardTokens = [bal, ldo];
    reward2WETH[bal] = [bal, weth];
    reward2WETH[ldo] = [ldo, wsteth, weth];
    WETH2deposit = [weth, bbaweth];
    poolIds[bal][weth] = 0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001;
    poolIds[wsteth][weth] = 0xfb5e6d0c1dfed2ba000fbc040ab8df3615ac329c000000000000000000000159;
    poolIds[weth][bbaweth] = 0xda1cd1711743e57dd57102e9e61b75f3587703da0000000000000000000003fc;
    router[ldo][wsteth] = camelotRouter;
  }
}

