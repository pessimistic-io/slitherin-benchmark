// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IAaveVault.sol";
import "./IActionPoolDcRouter.sol";

interface IAaveStrategy {
    struct MarginShort {
        uint256 supplyAmount;
        uint256 tradeOutAmount;
        uint256 tradeDeadline;
        uint16 referralCode;
        uint16 borrowRate;
        address[] path;
    }

    struct DecreaseShort {
        uint256 collateralAmount;
        uint256 tradeOutAmount;
        uint256 tradeDeadline;
        uint16 referralCode;
        uint16 borrowRate;
        address[] path;
    }

    event SwapEvent(address[] path, uint256 amountIn, uint256 amountOut);
    event MarginShortEvent(MarginShort);
    event DecreaseShortEvent(DecreaseShort);

    event UniSwapRouterSet(address newRouter, address user);

    function actionPool() external returns (IActionPoolDcRouter);

    function aaveVault() external returns (IAaveVault);

    function uniswapV2Router() external returns (IUniswapV2Router02);

    function setUniswapRouter(address newRouter) external;

    function swap(bytes memory _data) external returns (uint256 amountOut);

    function marginShort(bytes memory _data) external;

    function decreaseMarginShort(bytes memory _data) external;
}

