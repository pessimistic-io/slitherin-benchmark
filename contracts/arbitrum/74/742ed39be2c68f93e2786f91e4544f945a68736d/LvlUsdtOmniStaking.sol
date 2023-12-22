// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./interfaces_IERC20.sol";
import {IBurnableERC20} from "./IBurnableERC20.sol";
import {ILevelNormalVesting} from "./ILevelNormalVesting.sol";
import "./LevelOmniStaking.sol";

contract LvlUsdtOmniStaking is LevelOmniStaking {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBurnableERC20;

    uint8 constant VERSION = 2;

    ILevelNormalVesting public normalVestingLVL;
    address public stakingHelper;
    address public claimHelper;

    function reinit_changeStartEpoch() external reinitializer(VERSION) {
        uint256 _startTime = 1695823200; // Wednesday, September 27, 2023 2:00:00 PM
        epochs[currentEpoch].startTime = 0;
        epochs[currentEpoch].lastUpdateAccShareTime = 0;
        emit EpochEnded(currentEpoch, _startTime);

        currentEpoch++;
        epochs[currentEpoch].startTime = _startTime;
        epochs[currentEpoch].lastUpdateAccShareTime = _startTime;
        emit EpochStarted(currentEpoch, _startTime);
    }

    // =============== USER FUNCTIONS ===============
    function unstake(address _to, uint256 _amount) external override whenNotPaused nonReentrant {
        require(_to != address(0), "Invalid address");
        require(_amount > 0, "Invalid amount");
        address _sender = msg.sender;
        uint256 _reservedForVesting = 0;
        if (address(normalVestingLVL) != address(0)) {
            _reservedForVesting = normalVestingLVL.getReservedAmount(_sender);
        }
        require(_amount + _reservedForVesting <= stakedAmounts[_sender], "Insufficient staked amount");
        _updateCurrentEpoch();
        _updateUser(_sender, _amount, false);
        totalStaked -= _amount;
        stakeToken.safeTransfer(_to, _amount);
        emit Unstaked(_sender, _to, currentEpoch, _amount);
    }

    /**
     * @notice Support multiple claim, only `claimHelper` can call this function.
     */
    function claimRewardsOnBehalf(address _user, uint256 _epoch, address _to) external whenNotPaused nonReentrant {
        require(msg.sender == claimHelper, "Only claimHelper");
        _claimRewards(_user, _epoch, _to);
    }

    /**
     * @notice Support multiple claim, only `claimHelper` can call this function.
     */
    function claimRewardsToSingleTokenOnBehalf(
        address _user,
        uint256 _epoch,
        address _to,
        address _tokenOut,
        uint256 _minAmountOut
    ) external whenNotPaused nonReentrant {
        require(msg.sender == claimHelper, "Only claimHelper");
        _claimRewardsToSingleToken(_user, _epoch, _to, _tokenOut, _minAmountOut);
    }

    /**
     * @dev UNUSED: Update new business
     */
    function allocateReward(uint256 _epoch) external override onlyDistributorOrOwner {
        // doing nothing
    }

    /**
     * @dev @dev UNUSED: Update new business
     */
    function allocateReward(uint256 _epoch, address[] calldata _tokens, uint256[] calldata _amounts)
        external
        override
        onlyDistributorOrOwner
    {
        // doing nothing
    }

    function allocateReward(uint256 _epoch, uint256 _rewardAmount) external {
        require(msg.sender == stakingHelper, "Only stakingHelper");
        EpochInfo memory _epochInfo = epochs[_epoch];
        require(_epochInfo.endTime != 0, "Epoch not ended");
        require(_epochInfo.allocationTime == 0, "Reward allocated");
        require(_rewardAmount != 0, "Reward = 0");
        _epochInfo.totalReward = _rewardAmount;
        _epochInfo.allocationTime = block.timestamp;
        epochs[_epoch] = _epochInfo;
        LLP.safeTransferFrom(msg.sender, address(this), _rewardAmount);
        emit RewardAllocated(_epoch, _rewardAmount);
    }

    // =============== RESTRICTED ===============
    function setNormalVestingLVL(address _normalVestingLVL) external onlyOwner {
        require(_normalVestingLVL != address(0), "Invalid address");
        normalVestingLVL = ILevelNormalVesting(_normalVestingLVL);
        emit LevelNormalVestingSet(_normalVestingLVL);
    }

    function setStakingHelper(address _stakingHelper) external onlyOwner {
        stakingHelper = _stakingHelper;
        emit StakingHelperSet(_stakingHelper);
    }

    function setClaimHelper(address _claimHelper) external onlyOwner {
        claimHelper = _claimHelper;
        emit ClaimHelperSet(_claimHelper);
    }

    // =============== EVENTS ===============
    event LevelNormalVestingSet(address _normalVestingLVL);
    event StakingHelperSet(address _stakingHelper);
    event ClaimHelperSet(address _claimHelper);
}

