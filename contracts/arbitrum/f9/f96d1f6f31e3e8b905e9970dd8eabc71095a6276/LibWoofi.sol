// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {IWooPPV2} from "./IWooPPV2.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop, LibHop} from "./LibHop.sol";

library LibWoofi {
    using LibAsset for address;
    using LibHop for Hop;

    function swapWoofi(Hop memory h) internal {
        h.enforceSingleHop();
        h.path[0].approve(h.addr, h.amountIn);
        IWooPPV2(h.addr).swap(h.path[0], h.path[1], h.amountIn, 0, h.recipient, msg.sender);
    }
}

