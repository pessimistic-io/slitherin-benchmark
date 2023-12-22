// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ISwap} from "./ISwap.sol";

interface ILP {
    // Information needed to build a UniV2Pair
    struct LpInfo {
        ISwap swapper;
        bytes externalData;
    }

    function token0() external view returns (address);
    function token1() external view returns (address);

    function buildLP(uint256 _wethAmount, LpInfo memory _buildInfo) external returns (uint256);
    function breakLP(uint256 _lpAmount, LpInfo memory _swapData) external returns (uint256);
    function buildWithBothTokens(address token0, address token1, uint256 amount0, uint256 amount1)
        external
        returns (uint256);

    function ETHtoLP(uint256 _amount) external view returns (uint256);
    function performBreakAndSwap(uint256 _lpAmount, ISwap _swapper) external returns (uint256);
}

