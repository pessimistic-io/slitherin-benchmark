// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IOptionPricing } from "./IOptionPricing.sol";

// Libraries
import { SafeMath } from "./SafeMath.sol";
import { Black76 } from "./Black76.sol";
import { ABDKMathQuad } from "./ABDKMathQuad.sol";

contract MockOptionPricing is IOptionPricing, Black76 {
  using SafeMath for uint256;

  function getOptionPrice(
    int256 currentPrice,
    uint256 strike,
    int256 volatility,
    int256 amount,
    bool isPut,
    uint256 expiry,
    uint256 epochDuration
  ) external view override returns (uint256) {
    (int256 callPrice, int256 putPrice) = getPrice(
      currentPrice, //
      int256(strike),
      volatility,
      int256(expiry), // Number of days to expiry mul by 100
      int256(epochDuration),
      amount
    );

    uint256 minOptionPrice = uint256(currentPrice).div(1e2);

    if (isPut) {
      if (minOptionPrice > uint256(putPrice)) {
        return minOptionPrice;
      }
      return uint256(putPrice);
    }
    if (minOptionPrice > uint256(callPrice)) {
      return minOptionPrice;
    }
    return uint256(callPrice);
  }
}

