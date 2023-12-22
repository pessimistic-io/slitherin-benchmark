// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 Jones DAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

pragma solidity ^0.8.10;

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Governable, OperableKeepable} from "./OperableKeepable.sol";
import {IERC20} from "./IERC20.sol";
import {IERC4626} from "./IERC4626.sol";
import {IJonesGlpRewardDistributor} from "./IJonesGlpRewardDistributor.sol";
import {IJonesGlpRewardTracker} from "./IJonesGlpRewardTracker.sol";
import {IJonesGlpRewardsSwapper} from "./IJonesGlpRewardsSwapper.sol";
import {IIncentiveReceiver} from "./IIncentiveReceiver.sol";

contract JonesGlpRewardTracker is IJonesGlpRewardTracker, OperableKeepable, ReentrancyGuard {
    uint256 public constant PRECISION = 1e30;

    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address public immutable sharesToken;
    address public immutable rewardToken;

    IJonesGlpRewardDistributor public distributor;
    IJonesGlpRewardsSwapper public swapper;
    IIncentiveReceiver public incentiveReceiver;

    uint256 public wethRewards;
    uint256 public cumulativeRewardPerShare;
    mapping(address => uint256) public claimableReward;
    mapping(address => uint256) public previousCumulatedRewardPerShare;
    mapping(address => uint256) public cumulativeRewards;

    uint256 public totalStakedAmount;
    mapping(address => uint256) public stakedAmounts;

    constructor(address _sharesToken, address _rewardToken, address _distributor, address _incentiveReceiver)
        Governable(msg.sender)
        ReentrancyGuard()
    {
        if (_sharesToken == address(0)) {
            revert AddressCannotBeZeroAddress();
        }
        if (_rewardToken == address(0)) {
            revert AddressCannotBeZeroAddress();
        }
        if (_distributor == address(0)) {
            revert AddressCannotBeZeroAddress();
        }
        if (_incentiveReceiver == address(0)) {
            revert AddressCannotBeZeroAddress();
        }

        sharesToken = _sharesToken;
        rewardToken = _rewardToken;
        distributor = IJonesGlpRewardDistributor(_distributor);
        incentiveReceiver = IIncentiveReceiver(_incentiveReceiver);
    }

    // ============================= Operator functions ================================ //

    /**
     * @inheritdoc IJonesGlpRewardTracker
     */
    function stake(address _account, uint256 _amount) external onlyOperator returns (uint256) {
        if (_amount == 0) {
            revert AmountCannotBeZero();
        }
        _stake(_account, _amount);
        return _amount;
    }

    /**
     * @inheritdoc IJonesGlpRewardTracker
     */
    function withdraw(address _account, uint256 _amount) external onlyOperator returns (uint256) {
        if (_amount == 0) {
            revert AmountCannotBeZero();
        }

        _withdraw(_account, _amount);
        return _amount;
    }

    /**
     * @inheritdoc IJonesGlpRewardTracker
     */
    function claim(address _account) external onlyOperator returns (uint256) {
        return _claim(_account);
    }

    /**
     * @inheritdoc IJonesGlpRewardTracker
     */
    function updateRewards() external nonReentrant onlyOperatorOrKeeper {
        _updateRewards(address(0));
    }

    /**
     * @inheritdoc IJonesGlpRewardTracker
     */
    function depositRewards(uint256 _rewards) external onlyOperator {
        if (_rewards == 0) {
            revert AmountCannotBeZero();
        }
        uint256 totalShares = totalStakedAmount;
        IERC20(rewardToken).transferFrom(msg.sender, address(this), _rewards);

        if (totalShares != 0) {
            cumulativeRewardPerShare = cumulativeRewardPerShare + ((_rewards * PRECISION) / totalShares);
            emit UpdateRewards(msg.sender, _rewards, totalShares, cumulativeRewardPerShare);
        } else {
            IERC20(rewardToken).approve(address(incentiveReceiver), _rewards);
            incentiveReceiver.deposit(rewardToken, _rewards);
        }
    }

    // ============================= External functions ================================ //

    /**
     * @inheritdoc IJonesGlpRewardTracker
     */
    function claimable(address _account) external view returns (uint256) {
        uint256 shares = stakedAmounts[_account];
        if (shares == 0) {
            return claimableReward[_account];
        }
        uint256 totalShares = totalStakedAmount;
        uint256 pendingRewards = distributor.pendingRewards(address(this)) * PRECISION;
        uint256 nextCumulativeRewardPerShare = cumulativeRewardPerShare + (pendingRewards / totalShares);
        return claimableReward[_account]
            + ((shares * (nextCumulativeRewardPerShare - previousCumulatedRewardPerShare[_account])) / PRECISION);
    }

    /**
     * @inheritdoc IJonesGlpRewardTracker
     */
    function stakedAmount(address _account) external view returns (uint256) {
        return stakedAmounts[_account];
    }

    // ============================= Governor functions ================================ //

    /**
     * @notice Set a new distributor contract
     * @param _distributor New distributor address
     */
    function setDistributor(address _distributor) external onlyGovernor {
        if (_distributor == address(0)) {
            revert AddressCannotBeZeroAddress();
        }

        distributor = IJonesGlpRewardDistributor(_distributor);
    }

    /**
     * @notice Set a new swapper contract
     * @param _swapper New swapper address
     */
    function setSwapper(address _swapper) external onlyGovernor {
        if (_swapper == address(0)) {
            revert AddressCannotBeZeroAddress();
        }

        swapper = IJonesGlpRewardsSwapper(_swapper);
    }

    /**
     * @notice Set a new incentive receiver contract
     * @param _incentiveReceiver New incentive receiver address
     */
    function setIncentiveReceiver(address _incentiveReceiver) external onlyGovernor {
        if (_incentiveReceiver == address(0)) {
            revert AddressCannotBeZeroAddress();
        }

        incentiveReceiver = IIncentiveReceiver(_incentiveReceiver);
    }

    // ============================= Private functions ================================ //

    function _stake(address _account, uint256 _amount) private nonReentrant {
        IERC20(sharesToken).transferFrom(msg.sender, address(this), _amount);

        _updateRewards(_account);

        stakedAmounts[_account] = stakedAmounts[_account] + _amount;
        totalStakedAmount = totalStakedAmount + _amount;
        emit Stake(_account, _amount);
    }

    function _withdraw(address _account, uint256 _amount) private nonReentrant {
        _updateRewards(_account);

        uint256 amountStaked = stakedAmounts[_account];
        if (_amount > amountStaked) {
            revert AmountExceedsStakedAmount(); // Error camel case
        }

        stakedAmounts[_account] = amountStaked - _amount;

        totalStakedAmount = totalStakedAmount - _amount;

        IERC20(sharesToken).transfer(msg.sender, _amount);
        emit Withdraw(_account, _amount);
    }

    function _claim(address _account) private nonReentrant returns (uint256) {
        _updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        if (tokenAmount > 0) {
            IERC20(rewardToken).transfer(msg.sender, tokenAmount);
            emit Claim(_account, tokenAmount);
        }

        return tokenAmount;
    }

    function _updateRewards(address _account) private {
        uint256 rewards = distributor.distributeRewards(); // get new rewards for the distributor

        if (IERC4626(sharesToken).asset() == usdc && rewards > 0) {
            wethRewards = wethRewards + rewards;
            if (swapper.minAmountOut(wethRewards) > 0) {
                // enough weth to swap
                IERC20(weth).approve(address(swapper), wethRewards);
                rewards = swapper.swapRewards(wethRewards);
                wethRewards = 0;
            }
        }

        uint256 totalShares = totalStakedAmount;

        uint256 _cumulativeRewardPerShare = cumulativeRewardPerShare;
        if (totalShares > 0 && rewards > 0 && wethRewards == 0) {
            _cumulativeRewardPerShare = _cumulativeRewardPerShare + ((rewards * PRECISION) / totalShares);
            cumulativeRewardPerShare = _cumulativeRewardPerShare; // add new rewards to cumulative rewards
            // Information needed to calculate rewards
            emit UpdateRewards(_account, rewards, totalShares, cumulativeRewardPerShare);
        }

        // cumulativeRewardPerShare can only increase
        // so if cumulativeRewardPerShare is zero, it means there are no rewards yet
        if (_cumulativeRewardPerShare == 0) {
            return;
        }

        if (_account != address(0)) {
            uint256 shares = stakedAmounts[_account];

            uint256 accountReward =
                (shares * (_cumulativeRewardPerShare - previousCumulatedRewardPerShare[_account])) / PRECISION;
            uint256 _claimableReward = claimableReward[_account] + accountReward;
            claimableReward[_account] = _claimableReward; // add new user rewards to cumulative user rewards
            previousCumulatedRewardPerShare[_account] = _cumulativeRewardPerShare; // Important to not have more rewards than expected

            if (_claimableReward > 0 && shares > 0) {
                uint256 nextCumulativeReward = cumulativeRewards[_account] + accountReward;
                cumulativeRewards[_account] = nextCumulativeReward;
            }
        }
    }
}

