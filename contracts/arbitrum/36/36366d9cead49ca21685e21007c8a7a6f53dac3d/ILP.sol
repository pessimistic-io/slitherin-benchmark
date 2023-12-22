// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ISwap} from "./ISwap.sol";

interface ILP {
    function token0() external view returns (address);
    function token1() external view returns (address);

    function buildLP(uint256 _wethAmount, ISwap.SwapInfo memory _swapInfo) external returns (uint256);
    function breakLP(uint256 _lpAmount, ISwap.SwapInfo memory _swapinfo) external returns (uint256);
    function buildWithBothTokens(address token0, address token1, uint256 amount0, uint256 amount1)
        external
        returns (uint256);

    function ETHtoLP(uint256 _amount) external view returns (uint256);
    function performBreakAndSwap(uint256 _lpAmount, ISwap.SwapInfo memory _swapInfo) external returns (uint256);
}

