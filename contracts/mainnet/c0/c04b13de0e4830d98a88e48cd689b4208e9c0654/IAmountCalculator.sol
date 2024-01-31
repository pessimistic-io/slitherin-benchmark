// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

/// @title A helper contract for calculations related to order amounts
interface IAmountCalculator {
  /// @notice Calculates maker amount
  /// @return Result Floored maker amount
  function getMakerAmount(
    uint256 orderMakerAmount,
    uint256 orderTakerAmount,
    uint256 swapTakerAmount
  ) external pure returns (uint256);

  /// @notice Calculates taker amount
  /// @return Result Ceiled taker amount
  function getTakerAmount(
    uint256 orderMakerAmount,
    uint256 orderTakerAmount,
    uint256 swapMakerAmount
  ) external pure returns (uint256);
}

