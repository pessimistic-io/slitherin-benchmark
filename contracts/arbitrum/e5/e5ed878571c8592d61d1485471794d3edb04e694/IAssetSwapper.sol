// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.7.0;

/// @title AssetSwapper Interface
/// @author Dopex
interface IAssetSwapper {
  /// @dev Swaps between given `from` and `to` assets
  /// @param from From token address
  /// @param to To token address
  /// @param amount From token amount
  /// @param minAmountOut Minimum token amount to receive out
  /// @return To token amuount received
  function swapAsset(
    address from,
    address to,
    uint256 amount,
    uint256 minAmountOut
  ) external returns (uint256);
}

