// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Address.sol";
import "./SafeERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV3Router.sol";

library SwapTokensLibrary {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    function _getPath(
        address _from,
        address _to,
        address _baseCurrency
    ) internal pure returns (address[] memory) {
        address[] memory path;
        if (_from == _baseCurrency || _to == _baseCurrency) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = _baseCurrency;
            path[2] = _to;
        }
        return path;
    }

    function _liquidateRewards(
        address rewardToken,
        address underlying,
        address _dEXRouter,
        address _baseCurrency,
        uint256 minUnderlyingExpected
    ) internal {
        uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this));
        if (rewardAmount != 0) {
            IUniswapV2Router02 dEXRouter = IUniswapV2Router02(_dEXRouter);
            address[] memory path =
                _getPath(rewardToken, underlying, _baseCurrency);
            uint256 underlyingAmountOut =
                dEXRouter.getAmountsOut(rewardAmount, path)[path.length - 1];
            if (underlyingAmountOut != 0) {
                IERC20(rewardToken).safeApprove(_dEXRouter, rewardAmount);
                uint256 underlyingBalanceBefore =
                    IERC20(underlying).balanceOf(address(this));
                dEXRouter.swapExactTokensForTokens(
                    rewardAmount,
                    minUnderlyingExpected,
                    path,
                    address(this),
                    // solhint-disable-next-line not-rely-on-time
                    now
                );
                uint256 underlyingBalanceAfter =
                    IERC20(underlying).balanceOf(address(this));
                require(
                    underlyingBalanceAfter.sub(underlyingBalanceBefore) >=
                        minUnderlyingExpected,
                    "Not liquidated properly"
                );
            }
        }
    }

    // function _liquidateRewardsV3(
    //     address rewardToken,
    //     address underlying,
    //     address _dEXRouter,
    //     uint256 minUnderlyingExpected
    // ) internal {
    //     uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this));
    //     if (rewardAmount != 0) {
    //         IUniswapV3Router.ExactInputSingleParams memory params =
    //         IUniswapV3Router.ExactInputSingleParams({
    //             tokenIn: rewardToken,
    //             tokenOut: underlying,
    //             fee: poolFee,
    //             recipient: address(this),
    //             // solhint-disable-next-line not-rely-on-time
    //             deadline: now,
    //             amountIn: rewardAmount,
    //             amountOutMinimum: minUnderlyingExpected, // Need to change using oracle and slippage limit
    //             sqrtPriceLimitX96: 0
    //         });
    //         // The call to `exactInputSingle` executes the swap.
    //         IERC20(rewardToken).safeApprove(_dEXRouter, rewardAmount);
    //         uint256 underlyingBalanceBefore = IERC20(underlying).balanceOf(address(this));
    //         underlyingAmountOut = IUniswapV3Router.exactInputSingle(params);
    //         uint256 underlyingBalanceAfter = IERC20(underlying).balanceOf(address(this));
    //         require(
    //             underlyingBalanceAfter.sub(underlyingBalanceBefore) >=
    //                 minUnderlyingExpected,
    //             "Not liquidated properly"
    //         );
    //     }
    // }
}

