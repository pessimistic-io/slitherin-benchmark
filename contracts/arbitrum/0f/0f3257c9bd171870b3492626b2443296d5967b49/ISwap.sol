// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ILpsRegistry} from "./LpsRegistry.sol";

interface ISwap {
    struct SwapInfo {
        ISwap swapper;
        SwapData data;
    }

    struct SwapData {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 slippage;
        bytes externalData;
    }

    function swap(SwapData memory) external returns (uint256);
    function batchSwap(SwapData[] memory) external returns (uint256[] memory);
    function swapTokensToEth(address _token, uint256 _amount) external;
    function swapWethToUSDC(uint256 _amount) external;
    function swapUSDCToWeth(uint256 _amount) external;
    function USDCFromWeth(uint256 _amount) external view returns (uint256);
    function wethFromUSDC(uint256 _amount) external view returns (uint256);
    function USDCFromWethIn(uint256 _amount) external view returns (uint256);
    function wethFromUSDCIn(uint256 _amount) external view returns (uint256);
    function wethFromToken(address _token, uint256 _amount) external view returns (uint256);
    function RawUSDCToWETH(uint256 _amount) external view returns (uint256);
    function lpsRegistry() external view returns (ILpsRegistry);

    event AdapterSwap(
        address indexed swapper,
        address tokenIn,
        address tokenOut,
        address receiver,
        uint256 amountIn,
        uint256 amountOut
    );

    error NotImplemented();
}

