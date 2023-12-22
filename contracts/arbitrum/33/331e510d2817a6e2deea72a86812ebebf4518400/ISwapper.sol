// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface ISwapper {

    /**
     @notice Returns the value a the provided token in terms of ETH
     */
    function getETHValue(address token, uint amount) external view returns (uint value);

    /**
     * @notice Returns the value of the provided tokens in terms of ETH
     */
    function getETHValue(address[] memory tokens, uint[] memory amoutns) external view returns (uint value);

    /**
     @notice Get the amount of tokenIn needed to get amountOut tokens of tokenOut
     */
    function getAmountIn(address tokenIn, uint amountOut, address tokenOut) external view returns (uint amountIn);

    /**
     * @notice Returns the amount of tokenOut that can be obtained from amountIn worth of tokenIn
     */
    function getAmountOut(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut);

    /**
     * @notice Swap an exact amount of a token for another token
     * @dev slippage represents how much of a loss can be accepted
     * Max slippage is PRECISION, in which case all funds can be lost
     * Min slippage is 0, representing no loss of funds
     */
    function swapExactTokensForTokens(address tokenIn, uint amountIn, address tokenOut, uint slippage) external returns (uint amountOut);

    /**
     * @notice Swap a token for a specific amount of another token
     * @dev slippage represents how much of a loss can be accepted
     * Max slippage is PRECISION, in which case all funds can be lost
     * Min slippage is 0, representing no loss of funds
     */
    function swapTokensForExactTokens(address tokenIn, uint amountOut, address tokenOut, uint slippage) external returns (uint amountIn);
}
