//SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.17;

import "./UniswapV2Interface.sol";
import "./LoopyConstants.sol";

abstract contract Swap is LoopyConstants {
    /**
     * @dev Swaps a certain `amountIn` of a token for another token through Uniswap, ensuring a `minAmountOut` is returned. The pool fee of 100 is used to find the path of a pool and is specific for the BRIDGED_USDC/NATIVE_USDC pool.
     * @param token0Address The address of the token being swapped from.
     * @param token1Address The address of the token being swapped to.
     * @param amountIn The amount of `token0Address` tokens to be swapped.
     * @param minAmountOut The minimum amount of `token1Address` tokens to be returned.
     * @return The actual amount of `token1Address` tokens returned from the swap.
     *
     * This function uses the Uniswap protocol for token swaps. A swap involves trading a specific amount of one token to receive another token.
     * It specifies the addresses of the input and output tokens, the input amount, the minimum output amount, and a pool fee.
     * If the swap is successful, it returns the amount of `token1Address` tokens received.
     */
    function swapThroughUniswap(
        address token0Address,
        address token1Address,
        uint256 amountIn,
        uint256 minAmountOut
    ) public returns (uint256) {
        uint24 poolFee = 100;

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(token0Address, poolFee, token1Address),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        uint256 amountOut = UNI_ROUTER.exactInput(params);
        return amountOut;
    }

    /**
     * @dev Swaps a certain `amountIn` of a token for another token through Sushiswap, ensuring a `minAmountOut` is returned.
     * @param token0Address The address of the token being swapped from.
     * @param token1Address The address of the token being swapped to.
     * @param amountIn The amount of `token0Address` tokens to be swapped.
     * @param minAmountOut The minimum amount of `token1Address` tokens to be returned.
     *
     * This function uses the Sushiswap protocol for token swaps. It performs a swap of a specific amount of one token for another token.
     * It specifies the addresses of the input and output tokens, the input amount, and the minimum output amount.
     * This function only supports swapping tokens for tokens, if operations involve ETH, separate calls for wrapping/unwrapping to/from WETH should be made in the WETH contract.
     */
    function swapThroughSushiswap(
        address token0Address,
        address token1Address,
        uint256 amountIn,
        uint256 minAmountOut
    ) public {
        address[] memory path = new address[](2);
        path[0] = token0Address;
        path[1] = token1Address;
        address to = address(this);
        uint256 deadline = block.timestamp;
        SUSHI_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, minAmountOut, path, to, deadline);
    }
}

