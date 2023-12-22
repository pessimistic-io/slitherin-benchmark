// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IWombatRouter} from "./IWombatRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibWombat {
    using LibAsset for address;

    function getPoolAddress(bytes memory poolData) private pure returns (address poolAddress) {
        assembly {
            poolAddress := shr(96, mload(add(poolData, 32)))
        }
    }

    function getPoolAddresses(bytes[] memory poolDataList) private pure returns (address[] memory poolAddresses) {
        uint256 pdl = poolDataList.length;
        poolAddresses = new address[](pdl);

        for (uint256 i = 0; i < pdl; ) {
            poolAddresses[i] = getPoolAddress(poolDataList[i]);
            unchecked {
                i++;
            }
        }
    }

    function swapWombat(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].approve(h.addr, h.amountIn);
        amountOut = IWombatRouter(h.addr).swapExactTokensForTokens(
            h.path,
            getPoolAddresses(h.poolDataList),
            h.amountIn,
            0,
            address(this),
            block.timestamp
        );
    }
}

