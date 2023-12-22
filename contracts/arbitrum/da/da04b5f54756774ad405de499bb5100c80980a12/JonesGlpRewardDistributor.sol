// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 Jones DAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

pragma solidity ^0.8.10;

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Operable} from "./Operable.sol";
import {Governable} from "./Operable.sol";
import {IERC20} from "./IERC20.sol";
import {IJonesGlpRewardDistributor} from "./IJonesGlpRewardDistributor.sol";
import {IJonesGlpRewardsSplitter} from "./IJonesGlpRewardsSplitter.sol";
import {IIncentiveReceiver} from "./IIncentiveReceiver.sol";
import {IJonesGlpRewardTracker} from "./IJonesGlpRewardTracker.sol";

contract JonesGlpRewardDistributor is IJonesGlpRewardDistributor, Operable, ReentrancyGuard {
    uint256 public constant BASIS_POINTS = 1e12;
    uint256 public constant PRECISION = 1e30;

    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    IJonesGlpRewardsSplitter public splitter;
    IIncentiveReceiver public incentiveReceiver;

    address public stableTracker;
    address public glpTracker;

    uint256 public jonesPercentage;
    uint256 public stablePercentage;

    mapping(address => uint256) public rewardPools;

    constructor(IJonesGlpRewardsSplitter _splitter) Governable(msg.sender) ReentrancyGuard() {
        if (address(_splitter) == address(0)) {
            revert AddressCannotBeZeroAddress();
        }
        splitter = _splitter;
    }

    // ============================= Operator functions ================================ //

    /**
     * @inheritdoc IJonesGlpRewardDistributor
     */
    function splitRewards(uint256 _amount, uint256 _leverage, uint256 _utilization)
        external
        nonReentrant
        onlyOperator
    {
        if (_amount == 0) {
            return;
        }
        IERC20(weth).transferFrom(msg.sender, address(this), _amount);
        (uint256 glpRewards, uint256 stableRewards, uint256 jonesRewards) =
            splitter.splitRewards(_amount, _leverage, _utilization);

        IERC20(weth).approve(address(incentiveReceiver), jonesRewards);
        incentiveReceiver.deposit(weth, jonesRewards);
        address _stableTracker = stableTracker;
        address _glpTracker = glpTracker;
        rewardPools[_stableTracker] = rewardPools[_stableTracker] + stableRewards;
        rewardPools[_glpTracker] = rewardPools[_glpTracker] + glpRewards;

        // Information needed to calculate rewards per Vault
        emit SplitRewards(glpRewards, stableRewards, jonesRewards);
    }

    /**
     * @inheritdoc IJonesGlpRewardDistributor
     */
    function distributeRewards() external nonReentrant onlyOperator returns (uint256) {
        uint256 rewards = rewardPools[msg.sender];
        if (rewards == 0) {
            return 0;
        }
        rewardPools[msg.sender] = 0;
        IERC20(weth).transfer(msg.sender, rewards);
        return rewards;
    }

    // ============================= External functions ================================ //

    /**
     * @inheritdoc IJonesGlpRewardDistributor
     */
    function pendingRewards(address _pool) external view returns (uint256) {
        return rewardPools[_pool];
    }

    // ============================= Governor functions ================================ //

    /**
     * @notice Set the beneficiaries address of the GMX rewards
     * @param _splitter Jones reward splitter address
     */
    function setSplitter(IJonesGlpRewardsSplitter _splitter) external onlyGovernor {
        if (address(_splitter) == address(0)) {
            revert AddressCannotBeZeroAddress();
        }
        splitter = _splitter;
    }

    /**
     * @notice Set the beneficiaries address of the GMX rewards
     * @param _incentiveReceiver incentive receiver address
     * @param _stableTracker Stable Reward Tracker address
     * @param _glpTracker GLP Reward Tracker address
     */
    function setBeneficiaries(IIncentiveReceiver _incentiveReceiver, address _stableTracker, address _glpTracker)
        external
        onlyGovernor
    {
        if (address(_incentiveReceiver) == address(0)) {
            revert AddressCannotBeZeroAddress();
        }
        if (_stableTracker == address(0)) {
            revert AddressCannotBeZeroAddress();
        }
        if (_glpTracker == address(0)) {
            revert AddressCannotBeZeroAddress();
        }

        incentiveReceiver = _incentiveReceiver;
        stableTracker = _stableTracker;
        glpTracker = _glpTracker;
    }
}

