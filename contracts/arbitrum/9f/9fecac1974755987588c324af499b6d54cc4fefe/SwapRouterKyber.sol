// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
pragma abicoder v2;

import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./SwapRouterBase.sol";
import "./SwapRouterLib.sol";
import "./IKyberswap.sol";
import "./IWETH.sol";

contract SwapRouterKyber is SwapRouterBase {
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
            (, uint24 fee) = _findKyberswapPool(path[0], path[1], fees[0]);

            IKyberswapRouter.ExactInputSingleParams
                memory params = IKyberswapRouter.ExactInputSingleParams({
                    tokenIn: path[0],
                    tokenOut: path[1],
                    fee: fee,
                    recipient: recipient,
                    deadline: deadline,
                    amountIn: amountIn,
                    minAmountOut: amountOutMin,
                    limitSqrtP: 0
                });

            if (path[0] == _wETH) {
                amounts[0] = IKyberswapRouter(_swapRouter).swapExactInputSingle{
                    value: amountIn
                }(params);
            } else {
                amounts[0] = IKyberswapRouter(_swapRouter).swapExactInputSingle(
                    params
                );
            }
        } else {
            // Multihop
            for (uint256 i = 0; i < length - 1; ) {
                // Get fee
                (, fees[i]) = _findKyberswapPool(path[i], path[i + 1], fees[i]);

                unchecked {
                    ++i;
                }
            }

            IKyberswapRouter.ExactInputParams memory params = IKyberswapRouter
                .ExactInputParams({
                    path: SwapRouterLib.generateEncodedPathWithFee(path, fees),
                    recipient: recipient,
                    deadline: deadline,
                    amountIn: amountIn,
                    minAmountOut: amountOutMin
                });

            if (path[0] == _wETH) {
                amounts[0] = IKyberswapRouter(_swapRouter).swapExactInput{
                    value: amountIn
                }(params);
            } else {
                amounts[0] = IKyberswapRouter(_swapRouter).swapExactInput(
                    params
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
            (, uint24 fee) = _findKyberswapPool(path[0], path[1], fees[0]);

            IKyberswapRouter.ExactOutputSingleParams
                memory params = IKyberswapRouter.ExactOutputSingleParams({
                    tokenIn: path[0],
                    tokenOut: path[1],
                    fee: fee,
                    recipient: recipient,
                    deadline: deadline,
                    amountOut: amountOut,
                    maxAmountIn: amountInMax,
                    limitSqrtP: 0
                });

            if (path[0] == _wETH) {
                amounts[0] = IKyberswapRouter(_swapRouter)
                    .swapExactOutputSingle{value: amountInMax}(params);
            } else {
                amounts[0] = IKyberswapRouter(_swapRouter)
                    .swapExactOutputSingle(params);
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
                (, reverseFees[i]) = _findKyberswapPool(
                    reversePath[i],
                    reversePath[i + 1],
                    reverseFees[i]
                );

                unchecked {
                    ++i;
                }
            }

            IKyberswapRouter.ExactOutputParams memory params = IKyberswapRouter
                .ExactOutputParams({
                    path: SwapRouterLib.generateEncodedPathWithFee(
                        reversePath,
                        reverseFees
                    ),
                    recipient: recipient,
                    deadline: deadline,
                    amountOut: amountOut,
                    maxAmountIn: amountInMax
                });

            if (path[0] == _wETH) {
                amounts[0] = IKyberswapRouter(_swapRouter).swapExactOutput{
                    value: amountInMax
                }(params);
            } else {
                amounts[0] = IKyberswapRouter(_swapRouter).swapExactOutput(
                    params
                );
            }
        }

        // send back remained token
        if (path[0] == _wETH) {
            IKyberswapRouter(_swapRouter).refundEth(); // Take back leftover ETH
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
                uint256 quote = _getKyberswapQuote(
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
                uint256 quote = _getKyberswapQuote(
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
     * @notice get Kyberswap amount out for 1 decimal
     * if token 1 = wBNB (deciaml = 18, price = 331USD), token 2 = USDC(decmail = 6), amountOut = 331000000
     * @param tokenIn Address of token input
     * @param tokenOut Address of token output
     * @param _fee target fee
     * @return amountOut amount of tokenOut : decimal = tokenOut.decimals + 18 - tokenIn.decimals;
     */
    function _getKyberswapQuote(
        address tokenIn,
        address tokenOut,
        uint24 _fee
    ) private view returns (uint256 amountOut) {
        // Find Pool
        (address pool, ) = _findKyberswapPool(tokenIn, tokenOut, _fee);

        // Calulate Quote
        (uint160 sqrtPriceX96, , , ) = IKyberswapPool(pool).getPoolState();

        amountOut = SwapRouterLib.calcUniswapV3Quote(
            tokenIn,
            IKyberswapPool(pool).token0(),
            sqrtPriceX96
        );
    }

    /**
     * @notice Get pool, fee of Kyberswap
     * @param tokenA Address of TokenA
     * @param tokenB Address of TokenB
     * @param _fee target fee
     * @return pool address of pool
     * @return fee fee, 3000, 5000, 1000, if 0, pool isn't exist
     */
    function _findKyberswapPool(
        address tokenA,
        address tokenB,
        uint24 _fee
    ) private view returns (address pool, uint24 fee) {
        uint24[] memory fees = new uint24[](12);
        fees[0] = 8;
        fees[1] = 10;
        fees[2] = 40;
        fees[3] = 100;
        fees[4] = 250;
        fees[5] = 300;
        fees[6] = 500;
        fees[7] = 1000;
        fees[8] = 2000;
        fees[9] = 3000;
        fees[10] = 5000;
        fees[11] = 10000;

        return _findSwapPool(tokenA, tokenB, _fee, fees);
    }

    function _getPoolLiquidity(address pool)
        internal
        view
        override
        returns (uint256)
    {
        return IKyberswapPool(pool).totalSupply();
    }
}

