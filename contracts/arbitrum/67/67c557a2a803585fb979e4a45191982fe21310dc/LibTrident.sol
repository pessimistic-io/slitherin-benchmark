// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ITridentPool} from "./ITridentPool.sol";
import {ITridentBentoBoxV1} from "./ITridentBentoBoxV1.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

error TridentInvalidLengthsOfArrays();

library LibTrident {
    using LibAsset for address;

    function getPoolAddress(bytes memory poolData) private pure returns (address poolAddress) {
        assembly {
            poolAddress := shr(96, mload(add(poolData, 32)))
        }
    }

    function swapTrident(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].transfer(h.addr, h.amountIn);

        uint256 pl = h.path.length;
        for (uint256 i = 0; i < pl - 1; ) {
            address poolAddress = getPoolAddress(h.poolDataList[i]);
            bool isLast = i == pl - 2;

            if (i == 0) {
                ITridentBentoBoxV1(h.addr).deposit(h.path[i], h.addr, poolAddress, h.amountIn, 0);
            }

            amountOut = ITridentPool(poolAddress).swap(
                abi.encode(h.path[i], isLast ? address(this) : getPoolAddress(h.poolDataList[i + 1]), isLast)
            );

            unchecked {
                i++;
            }
        }
    }
}

