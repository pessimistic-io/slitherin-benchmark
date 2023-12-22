// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;
//pragma abicoder v2;

interface IEnigmaZapper {
    struct ZappParams {
        uint256 amountIn;
        address inputToken;
        address enigmaPool;
        bool swapForToken1;
        uint256 deadline;
        address token0;
        address token1;
        uint256 amount0OutMin;
        uint256 amount1OutMin;
    }
}

