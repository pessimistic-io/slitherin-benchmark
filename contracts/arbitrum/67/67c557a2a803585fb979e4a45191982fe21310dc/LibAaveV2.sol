// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ILendingPool} from "./ILendingPool.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibAaveV2 {
    using LibAsset for address;

    function swapAaveV2(Hop memory h) internal returns (uint256 amountOut) {
        uint256 pl = h.path.length;
        for (uint256 i = 0; i < pl - 1; ) {
            bytes memory poolData = h.poolDataList[i];
            uint8 operation;
            assembly {
                operation := shr(248, mload(add(poolData, 32)))
            }
            bool isDeposit = operation == 1;
            uint256 amountIn = i == 0 ? h.amountIn : amountOut;
            if (isDeposit) {
                h.path[i].approve(h.addr, amountIn);
                ILendingPool(h.addr).deposit(h.path[i], amountIn, address(this), 0);
                amountOut = h.amountIn;
            } else {
                amountOut = ILendingPool(h.addr).withdraw(h.path[i + 1], amountIn, address(this));
            }

            unchecked {
                i++;
            }
        }
    }
}

