// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ISwap} from "./ISwap.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibSaddle {
    using LibAsset for address;

    function getPoolAddress(bytes memory poolData) private pure returns (address poolAddress) {
        assembly {
            poolAddress := shr(96, mload(add(poolData, 32)))
        }
    }

    function swapSaddle(Hop memory h) internal returns (uint256 amountOut) {
        uint256 i;
        uint256 l = h.path.length;

        for (i = 0; i < l - 1; ) {
            address poolAddress = getPoolAddress(h.poolDataList[i]);
            h.path[i].approve(poolAddress, i == 0 ? h.amountIn : amountOut);
            uint8 tokenIndexFrom = ISwap(poolAddress).getTokenIndex(h.path[i]);
            uint8 tokenIndexTo = ISwap(poolAddress).getTokenIndex(h.path[i + 1]);
            amountOut = ISwap(poolAddress).swap(
                tokenIndexFrom,
                tokenIndexTo,
                i == 0 ? h.amountIn : amountOut,
                0,
                block.timestamp
            );

            unchecked {
                i++;
            }
        }
    }
}

