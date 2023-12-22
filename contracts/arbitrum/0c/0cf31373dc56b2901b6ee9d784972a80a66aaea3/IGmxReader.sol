// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGmxVault} from "./IGmxVault.sol";

interface IGmxReader {
    function getAmountOut(IGmxVault _vault, address _tokenIn, address _tokenOut, uint256 _amountIn)
        external
        view
        returns (uint256, uint256);
    function getMaxAmountIn(IGmxVault _vault, address _tokenIn, address _tokenOut) external view returns (uint256);
    function getPositions(
        address _vault,
        address _account,
        address[] memory _collateralTokens,
        address[] memory _indexTokens,
        bool[] memory _isLong
    ) external view returns (uint256[] memory);
}

