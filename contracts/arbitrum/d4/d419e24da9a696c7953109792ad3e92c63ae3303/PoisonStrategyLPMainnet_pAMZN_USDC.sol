//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PoisonStrategyLP.sol";

contract PoisonStrategyLPMainnet_pAMZN_USDC is PoisonStrategyLP {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x9B915D6eA56a7aBf03A96615AC76dFF2fD9dd60c);
    address poison = address(0x31C91D8Fb96BfF40955DD2dbc909B36E8b104Dde);
    address pAmzn = address(0xE656165d39419C03D588515c835d109E19221e1E);
    address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address masterChef = address(0x1b1Eb8CCC251deb3abD971B12bD8f34ac2A9a608);
    PoisonStrategyLP.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      masterChef,
      10
    );
    reward2WETH[poison] = [poison, usdc, weth];
    storedPairFee[usdc][weth] = 500;
    storedPairFee[poison][usdc] = 3000;
    WETH2deposit[pAmzn] = [weth, usdc, pAmzn];
    WETH2deposit[usdc] = [weth, usdc];
  }
}

