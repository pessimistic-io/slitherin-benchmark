// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ITWAPRelayer} from "./ITWAPRelayer.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibIntegralSize {
    using LibAsset for address;

    function swapIntegralSize(Hop memory h) internal returns (uint256 amountOut) {
        uint256 i;
        uint256 l = h.path.length;

        for (i = 0; i < l - 1; ) {
            h.path[i].approve(h.addr, h.amountIn);

            ITWAPRelayer(h.addr).sell(
                ITWAPRelayer.SellParams({
                    tokenIn: h.path[i],
                    tokenOut: h.path[i + 1],
                    amountIn: i == 0 ? h.amountIn : amountOut,
                    amountOutMin: 0,
                    wrapUnwrap: false,
                    to: address(this),
                    submitDeadline: uint32(block.timestamp)
                })
            );

            amountOut = h.path[i + 1].getBalance();

            unchecked {
                i++;
            }
        }
    }
}

