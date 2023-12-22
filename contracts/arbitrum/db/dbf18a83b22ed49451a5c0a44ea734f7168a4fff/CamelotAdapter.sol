//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {ICamelotRouter} from "./ICamelotRouter.sol";

abstract contract CamelotAdapter {
    ICamelotRouter camelotRouter;

    constructor(address _camelotRouter) {
        camelotRouter = ICamelotRouter(_camelotRouter);
    }

    function camelotSwap(uint256 amountIn, address[] memory path, address referrer, uint256 deadline) internal {
        IERC20(path[0]).approve(address(camelotRouter), amountIn);
        uint256[] memory amountOutMin = getAmountOut(amountIn, path);
        camelotRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOutMin[amountOutMin.length - 1], path, address(this), referrer, deadline
        );
    }

    function getAmountOut(uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        amounts = camelotRouter.getAmountsOut(amountIn, path);
    }
}

