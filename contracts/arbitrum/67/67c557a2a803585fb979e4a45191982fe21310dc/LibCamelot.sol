// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICamelotRouter} from "./ICamelotRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibCamelot {
    using LibAsset for address;

    function swapCamelot(Hop memory h) internal returns (uint256 amountOut) {
        uint256 l = h.path.length;
        h.path[0].approve(h.addr, h.amountIn);
        ICamelotRouter(h.addr).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            h.amountIn,
            0,
            h.path,
            address(this),
            address(0),
            block.timestamp
        );

        amountOut = h.path[l - 1].getBalance();
    }
}

