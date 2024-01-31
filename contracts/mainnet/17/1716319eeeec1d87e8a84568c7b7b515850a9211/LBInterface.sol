// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

interface LBInterface {

    function WETH() external view returns(address);

    function getAmountsInfo(uint256 _roundId) external view returns(address token0, address token1, uint256 targetAmount0, uint256 targetAmount1, uint256 amount0, uint256 amount1);

    function getMarketMakingInfo(uint256 _roundId) external view returns(uint24 fee, uint160 sqrtPriceX96, int24 tickLower, int24 tickUpper, address token0, address token1);
}
