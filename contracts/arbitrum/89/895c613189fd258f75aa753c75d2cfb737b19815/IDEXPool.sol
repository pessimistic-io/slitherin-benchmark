// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./IERC165.sol";

interface IDEXPool is IERC165 {
    function swapExactInputSingle(IERC20 from, IERC20 to,uint256 amountIn) external returns (uint256 amountOut);
    function swapExactOutputSingle(IERC20 from, IERC20 to, uint256 amountOut, uint256 amountInMaximum) external returns (uint256 amountIn);
    function getTotalLiquidity() external view returns (uint128);
    function getPrice() external view returns (uint256 price);
    function getPrecision() external view returns (uint256 precision);
    function getTokenAmounts(bool includeFee) external view returns (uint256[] memory amounts);
    function getTokens() external view returns (address[] memory tokens);
    function getTokenId() external view returns (uint256 tokenId);
    function getFeesToCollect() external view returns (uint256 feesCollectable0, uint256 feesCollectable1);
    function splitFundsIntoTokens(uint256 lowerPriceSqrtX96, uint256 upperPriceSqrtX96, uint256 funds, bool isFundsInToken0) external view returns (uint256 token0Amount, uint256 token1Amount);
    function getTicks() external view returns (int24 tickLower, int24 tickUpper);
    function mintNewPosition(uint256 amount0ToMint, uint256 amount1ToMint, int24 tickLower, int24 tickUpper, address leftOverRefundAddress) external returns (uint256, uint128, uint256, uint256);
    function increaseLiquidity(uint256 amount0Desired, uint256 amount1Desired, address leftOverRefundAddress) external returns (uint128, uint256, uint256);
    function decreaseLiquidity(uint128 liquidity, uint256 amount0Min, uint256 amount1Min) external returns (uint256, uint256);
    function collect(address recipient, uint128 amount0Max, uint128 amount1Max) external returns (uint256 amount0, uint256 amount1);
    function resetPosition() external;
}
