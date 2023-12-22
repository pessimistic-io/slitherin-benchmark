//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PoisonStrategyLP.sol";

contract PoisonStrategyLPMainnet_pSLVR_USDC is PoisonStrategyLP {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x5f586464c9DF5cA0C685798B4Fa092136f087BEc);
    address poison = address(0x31C91D8Fb96BfF40955DD2dbc909B36E8b104Dde);
    address pSlvr = address(0x867B1Cd06039Eb70385788a048B57F6d4fDC5Dbb);
    address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address masterChef = address(0x1b1Eb8CCC251deb3abD971B12bD8f34ac2A9a608);
    PoisonStrategyLP.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      masterChef,
      6
    );
    reward2WETH[poison] = [poison, usdc, weth];
    storedPairFee[usdc][weth] = 500;
    storedPairFee[poison][usdc] = 3000;
    WETH2deposit[pSlvr] = [weth, usdc, pSlvr];
    WETH2deposit[usdc] = [weth, usdc];
  }
}

