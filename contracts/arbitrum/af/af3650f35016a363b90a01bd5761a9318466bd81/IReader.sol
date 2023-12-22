//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { IVault } from "./IVault.sol";

interface IReader {
  function getMaxAmountIn(
    IVault _vault,
    address _tokenIn,
    address _tokenOut
  ) external view returns (uint256);

  function getAmountOut(IVault _vault, address _tokenIn, address _tokenOut, uint256 _amountIn) external view returns (uint256, uint256);
}

