// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IRouter} from "./IRouter.sol";
import {IRouterV2} from "./IRouterV2.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibSolidly {
    using LibAsset for address;

    function getRoute(address[] memory path, bool stable) private pure returns (IRouter.Route[] memory routes) {
        uint256 pl = path.length;
        routes = new IRouter.Route[](pl - 1);
        for (uint256 i = 0; i < pl - 1; ) {
            routes[i] = IRouter.Route({from: path[i], to: path[i + 1], stable: stable});

            unchecked {
                i++;
            }
        }
    }

    function getRouteV2(
        address[] memory path,
        bool stable,
        bytes[] memory poolDataList
    ) private pure returns (IRouterV2.Route[] memory routes) {
        uint256 pl = path.length;
        routes = new IRouterV2.Route[](pl - 1);
        for (uint256 i = 0; i < pl - 1; ) {
            bytes memory poolData = poolDataList[i];
            address factoryAddress;

            assembly {
                factoryAddress := shr(96, mload(add(poolData, 32)))
            }

            routes[i] = IRouterV2.Route({from: path[i], to: path[i + 1], stable: stable, factory: factoryAddress});

            unchecked {
                i++;
            }
        }
    }

    function swapSolidlyStable(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].approve(h.addr, h.amountIn);

        uint256[] memory amountOuts = h.poolDataList.length == 0
            ? IRouter(h.addr).swapExactTokensForTokens(
                h.amountIn,
                0,
                getRoute(h.path, true),
                address(this),
                block.timestamp
            )
            : IRouterV2(h.addr).swapExactTokensForTokens(
                h.amountIn,
                0,
                getRouteV2(h.path, true, h.poolDataList),
                address(this),
                block.timestamp
            );

        amountOut = amountOuts[amountOuts.length - 1];
    }

    function swapSolidlyVolatile(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].approve(h.addr, h.amountIn);

        uint256[] memory amountOuts = h.poolDataList.length == 0
            ? IRouter(h.addr).swapExactTokensForTokens(
                h.amountIn,
                0,
                getRoute(h.path, false),
                address(this),
                block.timestamp
            )
            : IRouterV2(h.addr).swapExactTokensForTokens(
                h.amountIn,
                0,
                getRouteV2(h.path, false, h.poolDataList),
                address(this),
                block.timestamp
            );

        amountOut = amountOuts[amountOuts.length - 1];
    }
}

