// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IGmxVault} from "./IGmxVault.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibGmx {
    using LibAsset for address;

    function swapGmx(Hop memory h) internal returns (uint256 amountOut) {
        uint256 i;
        uint256 l = h.path.length;

        for (i = 0; i < l - 1; ) {
            h.path[i].transfer(h.addr, i == 0 ? h.amountIn : amountOut);
            amountOut = IGmxVault(h.addr).swap(h.path[i], h.path[i + 1], address(this));

            unchecked {
                i++;
            }
        }
    }
}

