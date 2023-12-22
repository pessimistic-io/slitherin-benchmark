// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
pragma abicoder v2;

import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./ISwapRouter.sol";
import "./SwapRouterBase.sol";
import "./SwapRouterLib.sol";
import "./IUniswapV3.sol";
import "./IWETH.sol";

contract SwapRouterUniV3 is SwapRouterBase {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @notice Receive an as many output tokens as possible for an exact amount of input tokens.
     * @param amountIn TPayable amount of input tokens.
     * @param amountOutMin The minimum amount tokens to receive.
     * @param path (address[]) An array of token addresses. path.length must be >= 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * address(0) will be used for wrapped ETH
     * @param fees fees of pool
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapExactIn(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        uint24[] memory fees,
        uint256 deadline
    ) external payable override returns (uint256[] memory amounts) {
        uint256 length = path.length;
        address recipient = msg.sender;
        address _wETH = wETH;
        address _swapRouter = swapRouter;
        amounts = new uint256[](1);

        if (path[0] == _wETH) {
            require(msg.value >= amountIn, "SG0");

            // If too much ETH has been sent, send it back to sender
            if (msg.value > amountIn) {
                _send(payable(msg.sender), msg.value - amountIn);
            }
        } else {
            IERC20Upgradeable(path[0]).safeTransferFrom(
                msg.sender,
                address(this),
                amountIn
            );
            _approveTokenForSwapRouter(path[0], _swapRouter, amountIn);
        }

        if (path[length - 1] == _wETH) {
            recipient = address(this);
        }

        // Single
        if (length == 2) {
            // Check pool and fee
            (, uint24 fee) = _findUniswapV3Pool(path[0], path[1], fees[0]);

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: path[0],
                    tokenOut: path[1],
                    fee: fee,
                    recipient: recipient,
                    deadline: deadline,
                    amountIn: amountIn,
                    amountOutMinimum: amountOutMin,
                    sqrtPriceLimitX96: 0
                });

            if (path[0] == _wETH) {
                amounts[0] = ISwapRouter(_swapRouter).exactInputSingle{
                    value: amountIn
                }(params);
            } else {
                amounts[0] = ISwapRouter(_swapRouter).exactInputSingle(params);
            }
        } else {
            // Multihop

            for (uint256 i = 0; i < length - 1; ) {
                // Get fee
                (, fees[i]) = _findUniswapV3Pool(path[i], path[i + 1], fees[i]);

                unchecked {
                    ++i;
                }
            }

            ISwapRouter.ExactInputParams memory params = ISwapRouter
                .ExactInputParams({
                    path: SwapRouterLib.generateEncodedPathWithFee(path, fees),
                    recipient: recipient,
                    deadline: deadline,
                    amountIn: amountIn,
                    amountOutMinimum: amountOutMin
                });

            if (path[0] == _wETH) {
                amounts[0] = ISwapRouter(_swapRouter).exactInput{
                    value: amountIn
                }(params);
            } else {
                amounts[0] = ISwapRouter(_swapRouter).exactInput(params);
            }
        }

        // If receive ETH, unWrap it
        if (path[length - 1] == _wETH) {
            IWETH(_wETH).withdraw(
                IERC20Upgradeable(_wETH).balanceOf(address(this))
            );
            _send(payable(msg.sender), address(this).balance);
        }
    }

    /**
     * @notice Receive an exact amount of output tokens for as few input tokens as possible.
     * @param amountOut Payable amount of input tokens.
     * @param amountInMax The minimum amount tokens to input.
     * @param path (address[]) An array of token addresses. path.length must be >= 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * address(0) will be used for wrapped ETH
     * @param fees fees of pool
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapExactOut(
        uint256 amountOut,
        uint256 amountInMax,
        address[] memory path,
        uint24[] memory fees,
        uint256 deadline
    ) external payable override returns (uint256[] memory amounts) {
        uint256 remainedToken;
        uint256 length = path.length;
        address recipient = msg.sender;
        address _wETH = wETH;
        address _swapRouter = swapRouter;
        amounts = new uint256[](1);

        if (path[0] == _wETH) {
            require(msg.value >= amountInMax, "SG0");

            // If too much ETH has been sent, send it back to sender
            if (msg.value > amountInMax) {
                _send(payable(msg.sender), msg.value - amountInMax);
            }
        } else {
            IERC20Upgradeable(path[0]).safeTransferFrom(
                msg.sender,
                address(this),
                amountInMax
            );
            _approveTokenForSwapRouter(path[0], _swapRouter, amountInMax);
        }

        if (path[length - 1] == _wETH) {
            recipient = address(this);
        }

        // Single Swap
        if (length == 2) {
            // Check pool and fee
            (, uint24 fee) = _findUniswapV3Pool(path[0], path[1], fees[0]);

            ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
                .ExactOutputSingleParams({
                    tokenIn: path[0],
                    tokenOut: path[1],
                    fee: fee,
                    recipient: recipient,
                    deadline: deadline,
                    amountOut: amountOut,
                    amountInMaximum: amountInMax,
                    sqrtPriceLimitX96: 0
                });

            if (path[0] == _wETH) {
                amounts[0] = ISwapRouter(_swapRouter).exactOutputSingle{
                    value: amountInMax
                }(params);
            } else {
                amounts[0] = ISwapRouter(_swapRouter).exactOutputSingle(params);
            }
        } else {
            // Multihop

            // Get reverse path
            address[] memory reversePath = new address[](length);
            uint24[] memory reverseFees = new uint24[](length - 1);
            for (uint256 i = 0; i < length; ) {
                reversePath[i] = path[length - 1 - i];
                if (i < length - 1) reverseFees[i] = fees[length - 2 - i];

                unchecked {
                    ++i;
                }
            }

            for (uint256 i = 0; i < length - 1; ) {
                // Get fee
                (, reverseFees[i]) = _findUniswapV3Pool(
                    reversePath[i],
                    reversePath[i + 1],
                    reverseFees[i]
                );

                unchecked {
                    ++i;
                }
            }

            ISwapRouter.ExactOutputParams memory params = ISwapRouter
                .ExactOutputParams({
                    path: SwapRouterLib.generateEncodedPathWithFee(
                        reversePath,
                        reverseFees
                    ),
                    recipient: recipient,
                    deadline: deadline,
                    amountOut: amountOut,
                    amountInMaximum: amountInMax
                });

            if (path[0] == _wETH) {
                amounts[0] = ISwapRouter(_swapRouter).exactOutput{
                    value: amountInMax
                }(params);
            } else {
                amounts[0] = ISwapRouter(_swapRouter).exactOutput(params);
            }
        }

        // send back remained token
        if (path[0] == _wETH) {
            IUniswapV3Router(_swapRouter).refundETH(); // Take back leftover ETH
            remainedToken = address(this).balance;
            if (remainedToken > 0) {
                _send(payable(msg.sender), remainedToken);
            }
        } else {
            remainedToken = IERC20Upgradeable(path[0]).balanceOf(address(this));
            if (remainedToken > 0) {
                IERC20Upgradeable(path[0]).safeTransfer(
                    msg.sender,
                    remainedToken
                );
            }
        }

        // If receive ETH, unWrap it
        if (path[length - 1] == _wETH) {
            IWETH(_wETH).withdraw(
                IERC20Upgradeable(_wETH).balanceOf(address(this))
            );
            _send(payable(msg.sender), address(this).balance);
        }
    }

    function quoteExactInput(
        uint256 amountIn,
        address[] memory path,
        uint24[] memory fees
    ) public view override returns (uint256 amountOut) {
        if (amountIn > 0) {
            amountOut = amountIn;

            for (uint256 i = 0; i < path.length - 1; ) {
                uint256 quote = _getUniswapV3Quote(
                    path[i],
                    path[i + 1],
                    fees[i]
                );
                amountOut = (amountOut * quote) / BASE;

                unchecked {
                    ++i;
                }
            }
        }
    }

    function quoteExactOutput(
        uint256 amountOut,
        address[] memory path,
        uint24[] memory fees
    ) public view override returns (uint256 amountIn) {
        if (amountOut > 0) {
            amountIn = amountOut;

            for (uint256 i = path.length - 1; i > 0; ) {
                uint256 quote = _getUniswapV3Quote(
                    path[i],
                    path[i - 1],
                    fees[i - 1]
                );
                amountIn = (amountIn * quote) / BASE;

                unchecked {
                    --i;
                }
            }
        }
    }

    /**
     * @notice get UniswapV3 amount out for 1 decimal
     * if token 1 = wBNB (deciaml = 18, price = 331USD), token 2 = USDC(decmail = 6), amountOut = 331000000
     * @param tokenIn Address of token input
     * @param tokenOut Address of token output
     * @param _fee target fee
     * @return amountOut amount of tokenOut : decimal = tokenOut.decimals + 18 - tokenIn.decimals;
     */
    function _getUniswapV3Quote(
        address tokenIn,
        address tokenOut,
        uint24 _fee
    ) private view returns (uint256 amountOut) {
        // Find Pool
        (address uniswapV3Pool, ) = _findUniswapV3Pool(tokenIn, tokenOut, _fee);

        // Calulate Quote
        Slot0 memory slot0 = IUniswapV3Pool(uniswapV3Pool).slot0();

        amountOut = SwapRouterLib.calcUniswapV3Quote(
            tokenIn,
            IUniswapV3Pool(uniswapV3Pool).token0(),
            slot0.sqrtPriceX96
        );
    }

    /**
     * @notice Get pool, fee of uniswapV3
     * @param tokenA Address of TokenA
     * @param tokenB Address of TokenB
     * @param _fee target fee
     * @return pool address of pool
     * @return fee fee, 3000, 5000, 1000, if 0, pool isn't exist
     */
    function _findUniswapV3Pool(
        address tokenA,
        address tokenB,
        uint24 _fee
    ) private view returns (address pool, uint24 fee) {
        uint24[] memory fees = new uint24[](5);
        fees[0] = 100;
        fees[1] = 500;
        fees[2] = 3000;
        fees[3] = 5000;
        fees[4] = 10000;

        return _findSwapPool(tokenA, tokenB, _fee, fees);
    }

    function _getPoolLiquidity(address pool)
        internal
        view
        override
        returns (uint256)
    {
        return IUniswapV3Pool(pool).liquidity();
    }
}

