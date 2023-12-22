// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface IAnalizeModule {

    function moduleEstimation(address _uniswapRouterAddress, address _dexSwapRouterAddress, address _addrTokenA, address _addrTokenB) 
        external view returns (address tokenIn, uint256 amountIn);

    function moduleCalculateRatios(address _uniswapRouterAddress, address _dexSwapRouterAddress, address _addrTokenA, address _addrTokenB, uint256 _uniswapFee) 
        external view returns (uint256 ratioUniswap, uint256 ratioDexSwap, bool needForArbitrage, uint256 nTarget, uint256 nReal);
}

