//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PoisonStrategyLP.sol";

contract PoisonStrategyLPMainnet_pOIL_USDC is PoisonStrategyLP {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xb63E561193FAbD5482761c7aCC0711D7B784f845);
    address poison = address(0x31C91D8Fb96BfF40955DD2dbc909B36E8b104Dde);
    address pOil = address(0xb816688E4B70C9076BD87d45b5309F205ec2cf5f);
    address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address masterChef = address(0x1b1Eb8CCC251deb3abD971B12bD8f34ac2A9a608);
    PoisonStrategyLP.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      masterChef,
      5
    );
    reward2WETH[poison] = [poison, usdc, weth];
    storedPairFee[usdc][weth] = 500;
    storedPairFee[poison][usdc] = 3000;
    WETH2deposit[pOil] = [weth, usdc, pOil];
    WETH2deposit[usdc] = [weth, usdc];
  }
}

