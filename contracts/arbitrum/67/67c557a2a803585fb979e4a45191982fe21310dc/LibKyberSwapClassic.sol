// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";
import {IDMMExchangeRouter} from "./IDMMExchangeRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibKyberSwapClassic {
    using LibAsset for address;

    function getPoolAddress(bytes memory poolData) private pure returns (address poolAddress) {
        assembly {
            poolAddress := shr(96, mload(add(poolData, 32)))
        }
    }

    function swapKyberClassic(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].approve(h.addr, h.amountIn);

        uint256 l = h.path.length;
        address[] memory poolsPath = new address[](l - 1);
        IERC20[] memory path = new IERC20[](l);

        for (uint256 i = 0; i < l; ) {
            path[i] = IERC20(h.path[i]);

            if (i < l - 1) {
                poolsPath[i] = getPoolAddress(h.poolDataList[i]);
            }

            unchecked {
                i++;
            }
        }

        uint256[] memory amountOuts = IDMMExchangeRouter(h.addr).swapExactTokensForTokens(
            h.amountIn,
            0,
            poolsPath,
            path,
            address(this),
            block.timestamp
        );

        amountOut = amountOuts[amountOuts.length - 1];
    }
}

