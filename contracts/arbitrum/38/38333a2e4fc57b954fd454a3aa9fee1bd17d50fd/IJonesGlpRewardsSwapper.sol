// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IJonesGlpRewardsSwapper {
    event Swap(address indexed _tokenIn, uint256 _amountIn, address indexed _tokenOut, uint256 _amountOut);

    /**
     * @notice Swap eth rewards to USDC
     * @param _amountIn amount of rewards to swap
     * @return amount of USDC swapped
     */
    function swapRewards(uint256 _amountIn) external returns (uint256);

    /**
     * @notice Return min amount out of USDC due a weth in amount considering the slippage tolerance
     * @param _amountIn amount of weth rewards to swap
     * @return min output amount of USDC
     */
    function minAmountOut(uint256 _amountIn) external view returns (uint256);

    error InvalidSlippage();
}

