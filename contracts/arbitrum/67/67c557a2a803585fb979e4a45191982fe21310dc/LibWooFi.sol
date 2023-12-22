// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IWooPPV2} from "./IWooPPV2.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibWooFi {
    using LibAsset for address;

    function swapWooFi(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].transfer(h.addr, h.amountIn);

        uint256 pl = h.path.length;
        for (uint256 i = 0; i < pl - 1; ) {
            amountOut = IWooPPV2(h.addr).swap(
                h.path[i],
                h.path[i + 1],
                i == 0 ? h.amountIn : amountOut,
                0,
                i == pl - 2 ? address(this) : h.addr,
                msg.sender
            );

            unchecked {
                i++;
            }
        }
    }
}

