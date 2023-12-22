// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ISwapRouter.sol";
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
interface ILiquidator {
    function assetManager() external view returns (IAssetManager);

    function balanceSheet() external view returns (IBalanceSheet);

    function collateralTokenAddress() external view returns (address);

    function usdcAddress() external view returns (address);

    function liquidationFee() external view returns (uint256);

    function allowableSlippage() external view returns (uint256);

    function poolFee() external view returns (uint24);

    function swapRouter() external view returns (ISwapRouter);

    function setLiquidationCandidates() external;

    function executeLiquidations() external;

    function getLiquidatableCandidates()
        external
        view
        returns (address[] memory);

    function getReadyForLiquidationCandidates()
        external
        view
        returns (address[] memory);

    function withdrawERC20(
        address _to,
        uint256 _amount,
        address _tokenAddress
    ) external;

    function setLiquidationFee(uint256 _fee) external;

    function setAllowableSlippage(uint256 _allowableSlippage) external;

    function setPoolFee(uint24 _poolFee) external;
}

