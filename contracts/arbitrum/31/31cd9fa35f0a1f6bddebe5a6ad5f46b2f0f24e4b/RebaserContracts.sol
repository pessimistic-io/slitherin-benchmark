// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "./Rebaser.sol";

contract CVIUSDCRebaser is Rebaser {
  constructor(IVolatilityToken _volatilityToken, IUniswapV2Pair[] memory _uniswapPairs)
    Rebaser(_volatilityToken, _uniswapPairs)
  {}
}

contract CVIUSDCRebaser2X is Rebaser {
  constructor(IVolatilityToken _volatilityToken, IUniswapV2Pair[] memory _uniswapPairs)
    Rebaser(_volatilityToken, _uniswapPairs)
  {}
}
