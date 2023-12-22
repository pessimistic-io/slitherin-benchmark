// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import { SafeMath } from "./SafeMath.sol";
import { Black76 } from "./Black76.sol";
import { ABDKMathQuad } from "./ABDKMathQuad.sol";

// Contracts
import { Ownable } from "./Ownable.sol";

// Interfaces
import { IOptionPricing } from "./IOptionPricing.sol";

contract OptionPricingSimple is Ownable, IOptionPricing, Black76 {
  using SafeMath for uint256;

  // The max volatility possible
  uint256 public volatilityCap;

  constructor(uint256 _volatilityCap) {
    volatilityCap = _volatilityCap;
  }

  /*---- GOVERNANCE FUNCTIONS ----*/

  /// @notice updates volatility cap for an option pool
  /// @param _volatilityCap the new volatility cap
  /// @return whether volatility cap was updated
  function updateVolatilityCap(uint256 _volatilityCap)
    external
    onlyOwner
    returns (bool)
  {
    volatilityCap = _volatilityCap;

    return true;
  }

  /*---- VIEWS ----*/

  /**
   * @notice computes the option price (with liquidity multiplier)
   * @param currentPrice the current price
   * @param strike strike price
   * @param volatility volatility
   * @param amount amount
   * @param isPut isPut
   * @param expiry expiry timestamp
   */
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

    if (isPut) {
      return uint256(putPrice);
    }

    return uint256(callPrice);
  }
}

