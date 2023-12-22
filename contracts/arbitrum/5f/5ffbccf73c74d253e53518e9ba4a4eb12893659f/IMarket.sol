// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./Hints.sol";
import "./PancakeLpMarket.sol";

interface IMarket {
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address destination,
        bytes memory hints
    ) external returns (uint256);

    function estimateOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut, bytes memory hints);

    function estimateBurn(address lpToken, uint amountIn) external view returns (uint, uint);
}

