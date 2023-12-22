// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./IDexSwapper.sol";

abstract contract DexSwapper is IDexSwapper {
  address public immutable WETH9;
  address public immutable WETH9_STABLE_POOL;

  constructor(address _WETH9, address _WETH9_STABLE_POOL) {
    WETH9 = _WETH9;
    WETH9_STABLE_POOL = _WETH9_STABLE_POOL;
  }

  function _getPriceUSDOfTargetTokenNoDecimalsX128(
    address targetToken,
    uint256 priceX96,
    address token0,
    uint8 token0Decimals,
    address token1,
    uint8 token1Decimals
  ) internal view returns (uint256 priceUSDNoDecimalsX128) {
    if (token0 == WETH9 || token1 == WETH9) {
      uint256 usdWETHNoDecimalsX96 = _getWETHStableInfo();
      if (token1 == targetToken) {
        priceUSDNoDecimalsX128 =
          (usdWETHNoDecimalsX96 * 10 ** token1Decimals * 2 ** 128) /
          priceX96 /
          10 ** token0Decimals;
      } else {
        priceUSDNoDecimalsX128 =
          (priceX96 * usdWETHNoDecimalsX96 * 10 ** token0Decimals * 2 ** 128) /
          2 ** (96 * 2) /
          10 ** token1Decimals;
      }
    } else {
      if (token1 == targetToken) {
        priceUSDNoDecimalsX128 =
          (2 ** 96 * 10 ** token1Decimals * 2 ** 128) /
          priceX96 /
          10 ** token0Decimals;
      } else {
        priceUSDNoDecimalsX128 =
          (priceX96 * 10 ** token0Decimals * 2 ** 128) /
          2 ** 96 /
          10 ** token1Decimals;
      }
    }
  }

  function _getWETHStableInfo()
    internal
    view
    virtual
    returns (uint256 usdWETHNoDecimalsX96);
}

