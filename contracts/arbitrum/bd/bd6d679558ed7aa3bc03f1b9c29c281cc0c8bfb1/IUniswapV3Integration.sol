// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./INonfungiblePositionManager.sol";
import "./IUniswapV3Pool.sol";

interface IUniswapV3Integration {

    function mint(
        address uniswapPositionManager,
        address want,
        int24 tick0,
        int24 tick1
    ) external returns (uint tokenId);

    function swapToDesiredRatio(address provider, address want, uint allowedSlippage, int24 tick0, int24 tick1) external returns (address token, int slippage);

    function checkSkewness(address want, int24 tick0, int24 tick1) external view returns (bool needsCorrection);

    function increaseLiquidity(
        address uniswapPositionManager,
        uint tokenId,
        address want
    ) external;

    function decreaseLiquidity(
        address uniswapPositionManager,
        uint tokenId,
        uint128 liquidityToRemove
    ) external;

    function harvest(
        address uniswapPositionManager,
        uint tokenId
    ) external returns (uint256 amount0, uint256 amount1);

    function getRatio(
        address want,
        int24 tick0,
        int24 tick1
    ) external view returns (uint256 amount0, uint256 amount1);

    function pairPrice(address want, address token) external view returns (uint);

    function getPendingFees(
        address uniswapPositionManager,
        uint256 tokenId
    ) external view returns (uint256 feeAmt0, uint256 feeAmt1);

}

