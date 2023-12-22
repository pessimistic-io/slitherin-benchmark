// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
pragma abicoder v2;

import "./SafeERC20Upgradeable.sol";
import "./SwapRouterBase.sol";
import "./ICamelot.sol";
import "./IWETH.sol";

contract SwapRouterCamelot is SwapRouterBase {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bool public stable; // Determine whether use stable / violence pool

    function setStableStatus(bool _stable) external {
        stable = _stable;
    }

    /**
     * @notice Receive an as many output tokens as possible for an exact amount of input tokens.
     * @param amountIn TPayable amount of input tokens.
     * @param amountOutMin The minimum amount tokens to receive.
     * @param path (address[]) An array of token addresses. path.length must be >= 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * address(0) will be used for wrapped ETH
     * @param fee fee of pool
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapExactIn(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        uint24 fee,
        uint256 deadline
    ) public payable override returns (uint256[] memory amounts) {
        address _wETH = wETH;
        address _swapRouter = swapRouter;
        amounts = new uint256[](1);

        // swapExactETHForTokens
        if (path[0] == _wETH) {
            require(msg.value >= amountIn, "SG0");

            // If too much ETH has been sent, send it back to sender
            uint256 remainedToken = msg.value - amountIn;
            if (remainedToken > 0) {
                _send(payable(msg.sender), remainedToken);
            }

            ICamelotRouter(_swapRouter)
                .swapExactETHForTokensSupportingFeeOnTransferTokens{
                value: amountIn
            }(amountOutMin, path, msg.sender, ZERO_ADDRESS, deadline);

            amounts[0] = IERC20Upgradeable(path[path.length - 1]).balanceOf(
                msg.sender
            );
            return amounts;
        }

        IERC20Upgradeable(path[0]).safeTransferFrom(
            msg.sender,
            address(this),
            amountIn
        );
        _approveTokenForSwapRouter(path[0], _swapRouter, amountIn);

        // swapExactTokensForETH
        if (path[path.length - 1] == _wETH) {
            ICamelotRouter(_swapRouter)
                .swapExactTokensForETHSupportingFeeOnTransferTokens(
                    amountIn,
                    amountOutMin,
                    path,
                    msg.sender,
                    ZERO_ADDRESS,
                    deadline
                );
            amounts[0] = address(msg.sender).balance;
            return amounts;
        }

        // swapExactTokensForTokens

        ICamelotRouter(_swapRouter)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                msg.sender,
                ZERO_ADDRESS,
                deadline
            );

        amounts[0] = IERC20Upgradeable(path[path.length - 1]).balanceOf(
            msg.sender
        );
        return amounts;
    }

    /**
     * @notice Receive an exact amount of output tokens for as few input tokens as possible.
     * @param amountOut Payable amount of input tokens.
     * @param amountInMax The minimum amount tokens to input.
     * @param path (address[]) An array of token addresses. path.length must be >= 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * address(0) will be used for wrapped ETH
     * @param fee fee of pool
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapExactOut(
        uint256 amountOut,
        uint256 amountInMax,
        address[] memory path,
        uint24 fee,
        uint256 deadline
    ) external payable override returns (uint256[] memory amounts) {
        // Camelot doens't support swapExactOut
        return swapExactIn(amountInMax, amountOut, path, fee, deadline);
    }

    function quoteExactInput(
        uint256 amountIn,
        address[] memory path,
        uint24 fee
    ) public view override returns (uint256 amountOut) {
        if (amountIn > 0) {
            uint256[] memory amountOutList = ICamelotRouter(swapRouter)
                .getAmountsOut(amountIn, path);

            amountOut = amountOutList[amountOutList.length - 1];
        }
    }

    function quoteExactOutput(
        uint256 amountOut,
        address[] memory path,
        uint24 fee
    ) public view override returns (uint256 amountIn) {
        // Camelot doens't support swapExactOut
        amountIn = 0;
    }
}

