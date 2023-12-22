// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

/**
 * @title IGlpManager
 * @author Buooy
 * @notice Defines the basic interface for a GLP Manager.
 * @dev refer to https://github.com/gmx-io/gmx-contracts/blob/master/contracts/core/GlpManager.sol
 **/
interface IGlpManager {
  function getAum(bool maximise) external view returns (uint256);
  function getAumInUsdg(bool maximise) external view returns (uint256);
  function getMaxPrice(address _token) external view returns (uint256);
  function getMinPrice(address _token) external view returns (uint256);
  function getPrice(bool _maximise) external view returns (uint256);
}
