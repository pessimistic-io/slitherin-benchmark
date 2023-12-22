// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./Ownable.sol";
import "./IRouter.sol";
import "./HlpRouterUtils.sol";
import "./IERC20.sol";

/**
 * @dev this is an extension of HlpRouterUtils with an additional internal
 * method that swaps tokens in the hLP
 */
abstract contract HlpRouterUtilsV2 is Ownable, HlpRouterUtils {
    constructor(address _hlpRouter) HlpRouterUtils(_hlpRouter) {}

    /**
     * @dev swaps tokens in the handle liquidity pool
     * @param from the token to be sent
     * @param to the token to be received
     * @param amount the amount of {from} to send
     * @param signedQuoteData the price data to give to the hLP router
     */
    function _hlpSwap(
        address from,
        address to,
        uint256 amount,
        bytes calldata signedQuoteData
    ) internal {
        address[] memory path = new address[](2);
        path[0] = from;
        path[1] = to;

        // swap hlp token to fx token
        IERC20(from).approve(hlpRouter, amount);
        IRouter(hlpRouter).swap(
            path,
            amount,
            0, // no min out needed, will be handled when transferring out
            address(this),
            signedQuoteData
        );
    }
}

