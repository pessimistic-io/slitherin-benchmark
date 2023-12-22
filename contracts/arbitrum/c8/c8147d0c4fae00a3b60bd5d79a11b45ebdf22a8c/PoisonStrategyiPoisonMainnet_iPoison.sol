//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PoisonStrategyiPoison.sol";

contract PoisonStrategyiPoisonMainnet_iPoison is PoisonStrategyiPoison {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xDA016d31f2B52C73D7c1956E955ae8A507b305bB);
    address poison = address(0x31C91D8Fb96BfF40955DD2dbc909B36E8b104Dde);
    address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address masterChef = address(0x1b1Eb8CCC251deb3abD971B12bD8f34ac2A9a608);
    PoisonStrategyiPoison.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      masterChef,
      4
    );
    reward2WETH[poison] = [poison, usdc, weth];
    storedPairFee[usdc][weth] = 500;
    storedPairFee[poison][usdc] = 3000;
    WETH2deposit[poison] = [weth, usdc, poison];
  }
}

