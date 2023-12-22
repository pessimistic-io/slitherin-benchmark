// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IVault.sol";

/**
 * @title IReader
 * @author Buooy
 * @notice Defines the basic interface for a GMX Reader
 **/
interface IReader {
  function getAmountOut(IVault _vault, address _tokenIn, address _tokenOut, uint256 _amountIn) external view returns (uint256, uint256);
}
