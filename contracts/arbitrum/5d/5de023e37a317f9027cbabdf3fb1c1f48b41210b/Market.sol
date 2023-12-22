// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./Hints.sol";
import "./PancakeLpMarket.sol";

contract Market is OwnableUpgradeable {
    PancakeLpMarket public pancakeLpMarket;
    SingleMarket public singleMarket;

    constructor() initializer {
        __Ownable_init();
    }

    function setPancakeLpMarket(PancakeLpMarket _pancakeLpMarket) external onlyOwner {
        pancakeLpMarket = _pancakeLpMarket;
    }

    function setSingleMarket(SingleMarket _singleMarket) external onlyOwner {
        singleMarket = _singleMarket;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address destination,
        bytes memory hints
    ) external returns (uint256) {
        IERC20Upgradeable(tokenIn).transferFrom(address(msg.sender), address(this), amountIn);

        if (Hints.getIsPair(hints, tokenIn) || Hints.getIsPair(hints, tokenOut)) {
            IERC20Upgradeable(tokenIn).approve(address(pancakeLpMarket), amountIn);
            return pancakeLpMarket.swap(tokenIn, tokenOut, amountIn, amountOutMin, destination, hints);
        }

        IERC20Upgradeable(tokenIn).approve(address(singleMarket), amountIn);
        return singleMarket.swap(tokenIn, tokenOut, amountIn, amountOutMin, destination, hints);
    }

    function estimateOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool tokenInPair,
        bool tokenOutPair
    ) external view returns (uint256 amountOut, bytes memory hints) {
        if (tokenInPair || tokenOutPair) {
            (uint256 amountOut, bytes memory hints) = pancakeLpMarket.estimateOut(
                tokenIn,
                tokenOut,
                amountIn,
                tokenInPair,
                tokenOutPair
            );

            if (tokenInPair) {
                hints = Hints.merge2(hints, Hints.setIsPair(tokenIn));
            }

            if (tokenOutPair) {
                hints = Hints.merge2(hints, Hints.setIsPair(tokenOut));
            }

            return (amountOut, hints);
        }

        return singleMarket.estimateOut(tokenIn, tokenOut, amountIn);
    }
}

