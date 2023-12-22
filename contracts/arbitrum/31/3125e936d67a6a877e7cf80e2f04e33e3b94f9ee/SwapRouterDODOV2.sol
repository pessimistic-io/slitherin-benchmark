// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
pragma abicoder v2;

import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./SwapRouterBase.sol";
import "./IDODOSwap.sol";
import "./IWETH.sol";

contract SwapRouterDODOV2 is SwapRouterBase {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @notice Receive an as many output tokens as possible for an exact amount of input tokens.
     * @param amountIn TPayable amount of input tokens.
     * @param amountOutMin The minimum amount tokens to receive.
     * @param path (address[]) An array of token addresses. path.length must be > 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * address(0) will be used for wrapped ETH
     * path to swap path[0] : tokenIn, tokenOut, path[2...] pool, path[last] : tokenOut
     * @param fee fee of pool
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapExactIn(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        uint24 fee,
        uint256 deadline
    ) external payable override returns (uint256[] memory amounts) {
        return _swapDODOV2(amountIn, amountOutMin, path, false, deadline);
    }

    /**
     * @notice Receive an exact amount of output tokens for as few input tokens as possible.
     * @param amountOut Payable amount of input tokens.
     * @param amountInMax The minimum amount tokens to input.
     * @param path (address[]) An array of token addresses. path.length must be > 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * address(0) will be used for wrapped ETH
     * path to swap path[0] : tokenIn, tokenOut, path[2...] pool, path[last] : tokenOut
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
        // TODO: implement
        return _swapDODOV2(amountInMax, amountOut, path, false, deadline);
    }

    function quoteExactInput(
        uint256 amountIn,
        address[] memory path,
        uint24 fee
    ) public view override returns (uint256 amountOut) {
        require(path.length > 1, "SG5");

        address tokenIn = path[0];
        amountOut = amountIn;

        for (uint256 i = 1; i < path.length; ) {
            address pool = path[i];
            if (tokenIn == IDODOStorage(pool)._BASE_TOKEN_()) {
                (amountOut, ) = IDODOStorage(pool).querySellBase(
                    tx.origin,
                    amountOut
                );
                tokenIn = IDODOStorage(pool)._QUOTE_TOKEN_();
            } else if (tokenIn == IDODOStorage(pool)._QUOTE_TOKEN_()) {
                (amountOut, ) = IDODOStorage(pool).querySellQuote(
                    tx.origin,
                    amountOut
                );
                tokenIn = IDODOStorage(pool)._BASE_TOKEN_();
            } else {
                revert("SG6");
            }

            unchecked {
                ++i;
            }
        }
    }

    function quoteExactOutput(
        uint256 amountOut,
        address[] memory path,
        uint24 fee
    ) public view override returns (uint256 amountIn) {
        // TODO: implement
        return 0;
    }

    /**
     * @notice Receive an as many output tokens as possible for an exact amount of input tokens.
     * @param amountIn Amount of input tokens.
     * @param amountOutMin The minimum amount tokens to receive.
     * @param path path to swap path[0] : tokenIn, tokenOut, path[2...] pool, path[last] : tokenOut
     * @param isIncentive true : it is incentive
     * @param deadline Unix timestamp deadline
     */
    function _swapDODOV2(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        bool isIncentive,
        uint256 deadline
    ) private returns (uint256[] memory amounts) {
        address _wETH = wETH;
        address _swapRouter = swapRouter;

        require(path.length > 2, "SG5");
        amounts = new uint256[](1);

        // Get pairs, directions
        address[] memory dodoPairs = new address[](path.length - 2);
        uint256 directions = 0;
        {
            address tokenIn = path[0];
            uint256 i;

            for (i = 0; i < path.length - 2; ) {
                dodoPairs[i] = path[i + 1];

                if (IDODOStorage(path[i + 1])._BASE_TOKEN_() == tokenIn) {
                    directions = directions + (0 << i);
                    tokenIn = IDODOStorage(path[i + 1])._QUOTE_TOKEN_();
                } else {
                    directions = directions + (1 << i);
                    tokenIn = IDODOStorage(path[i + 1])._BASE_TOKEN_();
                }

                unchecked {
                    ++i;
                }
            }
        }

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

            // Approve to DODO_APPROVE
            _approveTokenForSwapRouter(
                path[0],
                IDODOApproveProxy(
                    IDODOV2Proxy02(_swapRouter)._DODO_APPROVE_PROXY_()
                )._DODO_APPROVE_(),
                amountIn
            );
        }

        // Swap
        if (path[0] == _wETH) {
            amounts[0] = IDODOV2Proxy02(_swapRouter).dodoSwapV2ETHToToken{
                value: amountIn
            }(
                path[path.length - 1],
                amountOutMin,
                dodoPairs,
                directions,
                isIncentive,
                deadline
            );

            IERC20Upgradeable(path[path.length - 1]).safeTransfer(
                msg.sender,
                amounts[0]
            );
        } else if (path[path.length - 1] == _wETH) {
            amounts[0] = IDODOV2Proxy02(_swapRouter).dodoSwapV2TokenToETH(
                path[0],
                amountIn,
                amountOutMin,
                dodoPairs,
                directions,
                isIncentive,
                deadline
            );

            _send(payable(msg.sender), amounts[0]);
        } else {
            amounts[0] = IDODOV2Proxy02(_swapRouter).dodoSwapV2TokenToToken(
                path[0],
                path[path.length - 1],
                amountIn,
                amountOutMin,
                dodoPairs,
                directions,
                isIncentive,
                deadline
            );

            IERC20Upgradeable(path[path.length - 1]).safeTransfer(
                msg.sender,
                amounts[0]
            );
        }

        // send back remained token
        uint256 remainedToken;
        if (path[0] == _wETH) {
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
    }
}

