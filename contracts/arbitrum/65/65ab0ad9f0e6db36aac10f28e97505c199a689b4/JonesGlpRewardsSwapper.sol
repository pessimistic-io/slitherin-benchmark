// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 Jones DAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

pragma solidity ^0.8.10;

import {Math} from "./Math.sol";
import {IERC20} from "./IERC20.sol";
import {IUniswapV2Router01} from "./IUniswapV2Router01.sol";
import {IAggregatorV3} from "./IAggregatorV3.sol";
import {IJonesGlpRewardTracker} from "./IJonesGlpRewardTracker.sol";
import {IJonesGlpRewardsSwapper} from "./IJonesGlpRewardsSwapper.sol";
import {Operable} from "./Operable.sol";
import {Governable} from "./Operable.sol";

contract JonesGlpRewardsSwapper is IJonesGlpRewardsSwapper, Operable {
    using Math for uint256;

    IERC20 public constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant stable = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IUniswapV2Router01 public constant SUSHI_ROUTER = IUniswapV2Router01(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IAggregatorV3 public constant ORACLE = IAggregatorV3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
    uint256 public slippageTolerance;

    constructor(uint256 _slippageTolerance) Governable(msg.sender) {
        _validateSlippage(_slippageTolerance);
        slippageTolerance = _slippageTolerance;
    }

    /**
     * @inheritdoc IJonesGlpRewardsSwapper
     */
    function swapRewards(uint256 _amountIn) external onlyOperator returns (uint256) {
        address[] memory path;
        path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(stable);

        uint256 amountOutStable = minAmountOut(_amountIn);

        WETH.transferFrom(msg.sender, address(this), _amountIn);

        WETH.approve(address(SUSHI_ROUTER), _amountIn);

        uint256[] memory swapOutputs = SUSHI_ROUTER.swapExactTokensForTokens(
            uint256(_amountIn), amountOutStable, path, msg.sender, block.timestamp
        );

        // Information needed to calculate stable rewards
        emit Swap(path[0], _amountIn, path[1], swapOutputs[1]);

        return swapOutputs[1]; //returned stable
    }

    function minAmountOut(uint256 _amountIn) public view returns (uint256) {
        uint256 amountOutStable = _getAmountOut(_amountIn);
        return amountOutStable.mulDiv(slippageTolerance, 100e12, Math.Rounding.Down);
    }

    /**
     * @notice Update slippage tolerance
     * @param _slippageTolerance amount of slippage to be tolerated
     */
    function updateSlippage(uint256 _slippageTolerance) external onlyGovernor {
        _validateSlippage(_slippageTolerance);
        slippageTolerance = _slippageTolerance;
    }

    function _getAmountOut(uint256 _amountInWeth) private view returns (uint256) {
        (, int256 lastPrice,,,) = ORACLE.latestRoundData();
        uint256 amountOutStable = uint256(lastPrice) * _amountInWeth;
        return amountOutStable / 1e20;
    }

    function _validateSlippage(uint256 _slippageTolerance) private pure {
        if (_slippageTolerance < 980e11 || _slippageTolerance > 999e11) {
            revert InvalidSlippage();
        }
    }
}

