// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IUniswapV2Router} from "./IUniswapV2Router.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibUniswapV2 {
    using LibAsset for address;

    function swapUniswapV2(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].approve(h.addr, h.amountIn);

        uint256[] memory amountOuts = IUniswapV2Router(h.addr).swapExactTokensForTokens(
            h.amountIn,
            0,
            h.path,
            address(this),
            block.timestamp
        );

        amountOut = amountOuts[amountOuts.length - 1];
    }
}

