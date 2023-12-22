// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20Metadata.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IAssetManager} from "./IAssetManager.sol";
import {IBalanceSheet} from "./IBalanceSheet.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @author DeFragDAO
interface IStrategist {
    function collateralToken() external view returns (IERC20Metadata);

    function usdc() external view returns (IERC20Metadata);

    function assetManager() external view returns (IAssetManager);

    function balanceSheet() external view returns (IBalanceSheet);

    function strategyFee() external view returns (uint256);

    function allowableSlippage() external view returns (uint256);

    function poolFee() external view returns (uint24);

    function swapRouter() external view returns (IUniswapV2Router02);

    function leverage2x(uint256 _depositAmount) external;

    function closeLeverage(uint256 _collateralAmount) external;

    function pauseStrategies() external;

    function unpauseStrategies() external;

    function withdrawEth(address _to, uint256 _amount) external;

    function withdrawERC20(
        address _to,
        uint256 _amount,
        address _tokenAddress
    ) external;

    function setStrategyFee(uint256 _fee) external;

    function setAllowableSlippage(uint256 _allowableSlippage) external;

    function setPoolFee(uint24 _poolFee) external;

    function setSwapRouter(address _swapRouterAddress) external;
}

