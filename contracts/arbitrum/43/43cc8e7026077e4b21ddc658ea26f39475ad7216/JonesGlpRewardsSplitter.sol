// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 Jones DAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

pragma solidity ^0.8.10;

import {Math} from "./Math.sol";
import {Governable, Operable} from "./Operable.sol";
import {IJonesGlpRewardsSplitter} from "./IJonesGlpRewardsSplitter.sol";

contract JonesGlpRewardsSplitter is IJonesGlpRewardsSplitter, Operable {
    using Math for uint256;

    uint256 public constant BASIS_POINTS = 1e12;

    uint256 public jonesPercentage;

    constructor() Governable(msg.sender) {}

    // ============================= Operator functions ================================ //

    /**
     * @inheritdoc IJonesGlpRewardsSplitter
     */
    function splitRewards(uint256 _amount, uint256 _leverage, uint256 _utilization)
        external
        view
        onlyOperator
        returns (uint256, uint256, uint256)
    {
        if (_leverage <= BASIS_POINTS) {
            return (_amount, 0, 0);
        }
        uint256 glpRewards = _amount.mulDiv(BASIS_POINTS, _leverage, Math.Rounding.Down);
        uint256 rewardRemainder = _amount - glpRewards;
        uint256 stableRewards =
            rewardRemainder.mulDiv(_stableRewardsPercentage(_utilization), BASIS_POINTS, Math.Rounding.Down);
        uint256 jonesRewards = rewardRemainder.mulDiv(jonesPercentage, BASIS_POINTS, Math.Rounding.Down);
        rewardRemainder = rewardRemainder - stableRewards - jonesRewards;
        glpRewards = glpRewards + rewardRemainder;

        return (glpRewards, stableRewards, jonesRewards);
    }

    // ============================= Governor functions ================================ //

    /**
     * @notice Set reward percetage for jones
     * @param _jonesPercentage Jones reward percentage
     */
    function setJonesRewardsPercentage(uint256 _jonesPercentage) external onlyGovernor {
        if (_jonesPercentage > BASIS_POINTS) {
            revert TotalPercentageExceedsMax();
        }
        jonesPercentage = _jonesPercentage;
    }

    // ============================= Private functions ================================ //

    function _stableRewardsPercentage(uint256 _utilization) private pure returns (uint256) {
        if (_utilization > (9935 * BASIS_POINTS) / 10000) {
            return BASIS_POINTS.mulDiv(50, 100);
        }
        if (_utilization <= (95 * BASIS_POINTS) / 100) {
            return BASIS_POINTS.mulDiv(30, 100);
        }
        return (_utilization * 2) - BASIS_POINTS.mulDiv(16, 10);
    }
}

