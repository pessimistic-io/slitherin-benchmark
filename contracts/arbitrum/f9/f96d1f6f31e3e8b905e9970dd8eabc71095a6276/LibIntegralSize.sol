// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {ITWAPRelayer} from "./ITWAPRelayer.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop, LibHop} from "./LibHop.sol";

library LibIntegralSize {
    using LibAsset for address;
    using LibHop for Hop;

    function swapIntegralSize(Hop memory h) internal {
        h.enforceSingleHop();
        h.path[0].approve(h.addr, h.amountIn);
        ITWAPRelayer(h.addr).sell(
            ITWAPRelayer.SellParams({
                tokenIn: h.path[0],
                tokenOut: h.path[1],
                amountIn: h.amountIn,
                amountOutMin: 0,
                wrapUnwrap: false,
                to: h.recipient,
                submitDeadline: uint32(block.timestamp)
            })
        );
    }
}

