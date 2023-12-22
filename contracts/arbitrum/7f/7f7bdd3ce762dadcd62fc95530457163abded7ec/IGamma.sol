// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IERC20} from "./IERC20.sol";

interface IUniProxy {
    function deposit(uint256 deposit0, uint256 deposit1, address to, address pos, uint256[4] memory minIn)
        external
        returns (uint256 shares);
    function getDepositAmount(address pos, address token, uint256 deposit)
        external
        view
        returns (uint256 amountStart, uint256 amountEnd);
}

interface IHypervisor is IERC20 {
    function withdraw(uint256 shares, address to, address from, uint256[4] memory minAmounts)
        external
        returns (uint256 amount0, uint256 amount1);
    function pool() external view returns (IUniswapV3Pool);
    function token0() external view returns (IERC20);
    function token1() external view returns (IERC20);
    function baseLower() external view returns (int24);
    function baseUpper() external view returns (int24);
    function limitLower() external view returns (int24);
    function limitUpper() external view returns (int24);
    function getBasePosition() external view returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function getLimitPosition() external view returns (uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IQuoter {
    function quoteExactInput(bytes memory path, uint256 amountIn) external returns (uint256 amountOut);
}

