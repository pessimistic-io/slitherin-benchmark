// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./IUniswapV2Router02.sol";

interface IFarmsUni {

    function addLiquidity(
        IUniswapV2Router02 router_,
        address token0_,
        address token1_,
        uint256 amount0_,
        uint256 amount1_,
        uint256 amountOutMin0_,
        uint256 amountOutMin1_
    ) external returns (uint256 amount0f, uint256 amount1f, uint256 lpRes);

    function withdrawLpAndSwap(
        address swapsUni_,
        address lpToken_,
        address[] memory tokens_,
        uint256 amountOutMin_,
        uint256 amountLp_
    ) external returns (uint256 amountTokenDesired);
}
