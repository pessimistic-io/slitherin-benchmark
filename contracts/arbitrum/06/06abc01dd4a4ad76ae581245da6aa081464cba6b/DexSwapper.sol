// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./FixedPoint96.sol";
import "./FixedPoint128.sol";
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
    uint256 priceNoDecimalsX96 = (priceX96 * 10 ** token0Decimals) /
      10 ** token1Decimals;

    if (token0 == WETH9 || token1 == WETH9) {
      uint256 usdWETHNoDecimalsX96 = _getUSDWETHNoDecimalsPriceX96();
      if (token1 == targetToken) {
        priceUSDNoDecimalsX128 =
          (FixedPoint128.Q128 * usdWETHNoDecimalsX96) /
          priceNoDecimalsX96;
      } else {
        priceUSDNoDecimalsX128 =
          (FixedPoint128.Q128 *
            ((priceNoDecimalsX96 * usdWETHNoDecimalsX96) / FixedPoint96.Q96)) /
          FixedPoint96.Q96;
      }
    } else {
      if (token1 == targetToken) {
        priceUSDNoDecimalsX128 =
          (FixedPoint128.Q128 * FixedPoint96.Q96) /
          priceNoDecimalsX96;
      } else {
        priceUSDNoDecimalsX128 =
          (FixedPoint128.Q128 * priceNoDecimalsX96) /
          FixedPoint96.Q96;
      }
    }
  }

  function _getUSDWETHNoDecimalsPriceX96()
    internal
    view
    virtual
    returns (uint256 usdWETHNoDecimalsX96);
}

