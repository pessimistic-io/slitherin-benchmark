// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPool} from "./IPool.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibMantisSwap {
    using LibAsset for address;

    function swapMantis(Hop memory h) internal returns (uint256 amountOut) {
        uint256 l = h.path.length;
        for (uint256 i = 0; i < l - 1; ) {
            uint256 amountIn = i == 0 ? h.amountIn : amountOut;
            h.path[i].approve(h.addr, amountIn);
            IPool(h.addr).swap(h.path[i], h.path[i + 1], address(this), amountIn, 0, block.timestamp);
            amountOut = h.path[i + 1].getBalance();

            unchecked {
                i++;
            }
        }
    }
}

