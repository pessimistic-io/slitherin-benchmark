// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IUniswapV3Tools {
    function createPool(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper,
        address recipient
    ) external payable returns (address pool);

    function exactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) external payable returns (uint256 amountOut);

    function principal(
        uint256 tokenId,
        uint160 sqrtRatioX96
    ) external view returns (uint256 amount0, uint256 amount1);

    function fees(uint256 tokenId) external view returns (uint256 amount0, uint256 amount1);

    function collect(
        uint256 tokenId,
        address recipient
    ) external payable returns (uint256 amount0, uint256 amount1);

    function nftManager() external returns(address);
}
