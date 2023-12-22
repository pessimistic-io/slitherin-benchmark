// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { ITraderJoeRouter } from "./ITraderJoeRouter.sol";
import { ITraderJoeLBRouter } from "./ITraderJoeLBRouter.sol";
import { IERC20Upgradeable } from "./ERC20_IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";

library SwapLib {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    enum Dex {
        AvalancheTraderJoe,
        AvalancheTraderJoeV2,
        ArbitrumTraderJoe,
        ArbitrumTraderJoeV2
    }

    struct Router {
        Dex dex;
        address router;
    }

    function swapTokensForTokens(
        Router memory router,
        uint256 amountIn,
        address[] memory path,
        uint256[] memory binSteps
    ) internal returns (uint256 amountOut) {
        if (router.dex == Dex.AvalancheTraderJoe) {
            ITraderJoeRouter traderjoeRouter = ITraderJoeRouter(router.router);

            IERC20Upgradeable(path[0]).safeIncreaseAllowance(
                address(traderjoeRouter),
                amountIn
            );

            amountOut = traderjoeRouter.swapExactTokensForTokens(
                amountIn,
                0,
                path,
                address(this),
                // solhint-disable-next-line not-rely-on-time
                block.timestamp
            )[path.length - 1];
        } else if (
            router.dex == Dex.AvalancheTraderJoeV2 ||
            router.dex == Dex.ArbitrumTraderJoeV2
        ) {
            ITraderJoeLBRouter traderjoeLBRouter = ITraderJoeLBRouter(
                router.router
            );

            IERC20Upgradeable(path[0]).approve(
                address(traderjoeLBRouter),
                amountIn
            );

            amountOut = traderjoeLBRouter.swapExactTokensForTokens(
                amountIn,
                0,
                binSteps,
                path,
                address(this),
                // solhint-disable-next-line not-rely-on-time
                block.timestamp
            );
        } else {
            // solhint-disable-next-line reason-string
            revert("SwapLib: Invalid swap service provider");
        }
    }

    function swapNativeForTokens(
        Router memory router,
        uint256 amountIn,
        address[] memory path
    ) internal returns (uint256 amountOut) {
        if (router.dex == Dex.AvalancheTraderJoe) {
            amountOut = ITraderJoeRouter(router.router).swapExactAVAXForTokens{
                value: amountIn
            }(
                0,
                path,
                address(this),
                // solhint-disable-next-line not-rely-on-time
                block.timestamp
            )[path.length - 1];
        } else {
            // solhint-disable-next-line reason-string
            revert("SwapLib: Invalid swap service provider");
        }
    }

    function swapTokensForNative(
        Router memory router,
        uint256 amountIn,
        address[] memory path
    ) internal returns (uint256 amountOut) {
        if (router.dex == Dex.AvalancheTraderJoe) {
            ITraderJoeRouter traderjoeRouter = ITraderJoeRouter(router.router);

            IERC20Upgradeable(path[0]).safeIncreaseAllowance(
                address(traderjoeRouter),
                amountIn
            );

            amountOut = traderjoeRouter.swapExactTokensForAVAX(
                amountIn,
                0,
                path,
                address(this),
                // solhint-disable-next-line not-rely-on-time
                block.timestamp
            )[path.length - 1];
        } else {
            // solhint-disable-next-line reason-string
            revert("SwapLib: Invalid swap service provider");
        }
    }

    function getAmountOut(
        Router memory router,
        uint256 amountIn,
        address[] memory path
    ) internal view returns (uint256) {
        if (router.dex == Dex.AvalancheTraderJoe) {
            return
                ITraderJoeRouter(router.router).getAmountsOut(amountIn, path)[
                    path.length - 1
                ];
        } else {
            // solhint-disable-next-line reason-string
            revert("SwapLib: Invalid swap service provider");
        }
    }
}

