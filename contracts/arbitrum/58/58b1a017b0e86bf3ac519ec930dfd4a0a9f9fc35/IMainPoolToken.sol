// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";

interface IMainPoolToken {
    function token() external view returns (IERC20);
    function stable() external view returns (IERC20);
    function getAmountOutTokenToStable(uint256 tokenAmount) external returns (uint256 stableAmount);
    function getAmountOutStableToToken(uint256 stableAmount) external returns (uint256 tokenAmount);
    function applyCoeffCorrectionToSell(uint256 stableAmount) external returns (uint256 stableAmountWithCorrection);
    function swapTokenToStable(uint256 tokenAmount, address to) external returns (uint256 stableAmountOut);
    function swapStableToToken(uint256 stableAmount, address to) external returns (uint256 tokenAmount);
}

