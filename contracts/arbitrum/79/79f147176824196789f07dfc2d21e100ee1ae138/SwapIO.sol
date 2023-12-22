// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;

import "./Math.sol";
import "./IPriceCurve.sol";

struct FillStateParams {
  uint64 id;
  uint128 startX96;
  bool sign;
}

contract SwapIO {
  using Math for uint;

  uint256 internal constant Q96 = 0x1000000000000000000000000;

  // given an input amount to a limitSwapExactInput function, return the output amount
  function limitSwapExactInput_getOutput (
    uint input,
    uint filledInput,
    uint tokenInAmount,
    IPriceCurve priceCurve,
    bytes memory priceCurveParams
  ) public pure returns (uint output) {
    if (filledInput >= tokenInAmount) {
      return 0;
    }
    output = priceCurve.getOutput(
      tokenInAmount,
      filledInput,
      input,
      priceCurveParams
    );
  }

  // given an output to a limitSwapExactInput function, return the input
  function limitSwapExactInput_getInput () public pure returns (uint input) {
    revert("NOT IMPLEMENTED");
  }

  // given an input to a limitSwapExactOutput function, return the output
  function limitSwapExactOutput_getOutput (
  ) public pure returns (uint output) {
    revert("NOT IMPLEMENTED");
  }

  // given an ouput to a limitSwapExactOutput function, return the input
  function limitSwapExactOutput_getInput (
    uint output,
    uint filledOutput,
    uint tokenOutAmount,
    IPriceCurve priceCurve,
    bytes memory priceCurveParams
  ) public pure returns (uint input) {
    if (filledOutput >= tokenOutAmount) {
      return 0;
    }

    // the getOutput() function is used to calculate the input amount,
    // because for `limitSwapExactOutput` the price curve is inverted
    input = priceCurve.getOutput(
      tokenOutAmount,
      filledOutput,
      output,
      priceCurveParams
    );
  }

  // given fillState and total, return the amount unfilled
  function getUnfilledAmount (FillStateParams memory fillStateParams, int fillStateX96, uint totalAmount) public pure returns (uint unfilledAmount) {
    unfilledAmount = totalAmount - getFilledAmount(fillStateParams, fillStateX96, totalAmount);
  }

  // given fillState and total, return the amount filled
  function getFilledAmount (FillStateParams memory fillStateParams, int fillStateX96, uint totalAmount) public pure returns (uint filledAmount) {
    filledAmount = getFilledPercentX96(fillStateParams, fillStateX96).mulDiv(totalAmount, Q96);
  }

  // given fillState, return the percent filled
  function getFilledPercentX96 (FillStateParams memory fillStateParams, int fillStateX96) public pure returns (uint filledPercentX96) {
    int8 i = fillStateParams.sign ? int8(1) : -1;
    int j = fillStateParams.sign ? int(0) : int(Q96);
    filledPercentX96 = uint((fillStateX96 + int128(fillStateParams.startX96)) * i + j);
  }

  // given exact input, price, and fee info, return output and fee amounts
  function marketSwapExactInput_getOutput (
    uint input,
    uint priceX96,
    uint24 feePercent,
    uint feeMin
  ) public pure returns (
    uint output,
    uint fee,
    uint outputWithFee
  ) {
    output = calcSwapAmount(priceX96, input);
    fee = calcFee(output, feePercent, feeMin);
    outputWithFee = output - fee;
  }

  // given exact output, price, and fee info, return input and fee amounts
  function marketSwapExactOutput_getInput (
    uint output,
    uint priceX96,
    uint24 feePercent,
    uint feeMin
  ) public pure returns (
    uint input,
    uint fee,
    uint inputWithFee
  ) {
    input = calcSwapAmount(priceX96, output);
    fee = calcFee(input, feePercent, feeMin);
    inputWithFee = input + fee;
  }

  // given price and amount0, return amount1
  function calcSwapAmount (uint priceX96, uint amount0) public pure returns (uint amount1) {
    amount1 = priceX96 * amount0 / Q96;
  }

  // given amount, fee %, and fee minimum, return the fee
  function calcFee (uint amount, uint24 feePercent, uint feeMin) public pure returns (uint fee) {
    fee = amount.mulDiv(feePercent, 10**6);
    if (fee < feeMin) {
      fee = feeMin;
    }
  }

}

