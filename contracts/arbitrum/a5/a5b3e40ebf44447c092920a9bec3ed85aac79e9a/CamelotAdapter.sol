//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ICamelotRouter} from "./ICamelotRouter.sol";

abstract contract CamelotAdapter {
    using SafeERC20 for IERC20;
    ICamelotRouter public immutable camelotRouter;

    constructor(address _camelotRouter) {
        camelotRouter = ICamelotRouter(_camelotRouter);
    }

    function camelotSwap(uint256 amountIn, address[] memory path, address referrer, uint256 deadline) internal {
        amountIn = amountIn == 0 ? IERC20(path[0]).balanceOf(address(this)) : amountIn;
        if (IERC20(path[0]).allowance(address(this), address(camelotRouter)) < amountIn) {
            if(IERC20(path[0]).allowance(address(this), address(camelotRouter)) > 0) {
                IERC20(path[0]).safeDecreaseAllowance(address(camelotRouter), IERC20(path[0]).allowance(address(this), address(camelotRouter)));
            }
            IERC20(path[0]).approve(address(camelotRouter), type(uint256).max);
        }
        uint256[] memory amountOutMin = getAmountOut(amountIn, path);
        camelotRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOutMin[amountOutMin.length - 1], path, address(this), referrer, deadline
        );
    }

    function getAmountOut(uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        amounts = camelotRouter.getAmountsOut(amountIn, path);
    }
}

