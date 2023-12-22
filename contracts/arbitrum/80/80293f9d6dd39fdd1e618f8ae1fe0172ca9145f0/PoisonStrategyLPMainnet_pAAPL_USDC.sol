//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PoisonStrategyLP.sol";

contract PoisonStrategyLPMainnet_pAAPL_USDC is PoisonStrategyLP {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x410B7C383a0dF3c56C63E44b2e4Cb752A1350b32);
    address poison = address(0x31C91D8Fb96BfF40955DD2dbc909B36E8b104Dde);
    address pAapl = address(0xf8f636BB3Be1fEEB979E1ea281389b49CF3a6853);
    address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address masterChef = address(0x1b1Eb8CCC251deb3abD971B12bD8f34ac2A9a608);
    PoisonStrategyLP.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      masterChef,
      11
    );
    reward2WETH[poison] = [poison, usdc, weth];
    storedPairFee[usdc][weth] = 500;
    storedPairFee[poison][usdc] = 3000;
    WETH2deposit[pAapl] = [weth, usdc, pAapl];
    WETH2deposit[usdc] = [weth, usdc];
  }
}

