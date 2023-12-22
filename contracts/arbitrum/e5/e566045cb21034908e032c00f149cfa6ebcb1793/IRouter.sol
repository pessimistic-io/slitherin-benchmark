// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

/**
 * @title IRouter
 * @author Buooy
 * @notice Defines the basic interface for a GMX Router.
 **/
interface IRouter {
  function swap(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver) external;
}
