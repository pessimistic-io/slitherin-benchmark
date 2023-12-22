// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {ISwap} from "./ISwap.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop, LibHop} from "./LibHop.sol";

library LibSaddle {
    using LibAsset for address;
    using LibHop for Hop;

    function getPoolAddress(bytes memory poolData) private pure returns (address poolAddress) {
        assembly {
            poolAddress := shr(96, mload(add(poolData, 32)))
        }
    }

    function swapSaddle(Hop memory h) internal {
        h.enforceSingleHop();
        address poolAddress = getPoolAddress(h.poolDataList[0]);
        h.path[0].approve(poolAddress, h.amountIn);
        uint8 tokenIndexFrom = ISwap(poolAddress).getTokenIndex(h.path[0]);
        uint8 tokenIndexTo = ISwap(poolAddress).getTokenIndex(h.path[1]);
        ISwap(poolAddress).swap(tokenIndexFrom, tokenIndexTo, h.amountIn, 0, block.timestamp);
        h.enforceTransferToRecipient();
    }
}

