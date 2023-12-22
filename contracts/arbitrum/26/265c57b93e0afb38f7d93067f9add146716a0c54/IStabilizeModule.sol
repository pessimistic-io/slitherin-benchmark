// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface IStabilizeModule {

    function moduleEstimation(address _dexSwapRouterAddress, address _usdexAddress, address _usdcAddress, uint8 _usdexDecimals, uint8 _usdcDecimals) 
        external view returns (address tokenIn, uint256 amountIn, uint256 profit, uint256 ratio);
}

