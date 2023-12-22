// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {IRouter} from "./IRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibGmx {
    using LibAsset for address;

    function swapGmx(Hop memory h) internal {
        h.path[0].approve(h.addr, h.amountIn);
        IRouter(h.addr).swap(h.path, h.amountIn, 0, h.recipient);
    }
}

