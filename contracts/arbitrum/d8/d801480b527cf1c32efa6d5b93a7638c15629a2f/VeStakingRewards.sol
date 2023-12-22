// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.3;

import { IVotingEscrow } from "./IVotingEscrow.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Ownable } from "./Ownable.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

contract VeStakingRewards is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =============================================================
    //                          Events
    // =============================================================

    event RewardClaimed(address indexed account, uint256[] rewardSchedule, uint256[] rewardAmount);
    event RewardScheduleCreated(uint256 blockNumberRewardSchedule, uint256 totalRewards, uint256 createdTime);
    event RewardScheduleEdited(uint256 blockNumberRewardSchedule, uint256 oldTotalRewards, uint256 newTotalRewards);
    event RewardScheduleDeleted(uint256 blockNumberRewardSchedule);
    event FundManagerAdded(address indexed account);
    event FundManagerRemoved(address indexed account);

    // =============================================================
    //                          Errors
    // =============================================================

    error HAS_CLAIMED(); // 0xd43cb521
    error REWARD_SCHEDULE_EXIST(); // 0xfbc81195
    error INVALID_REWARD_SCHEDULE(); // 0xcda56a42
    error REWARD_CLAIM_NOT_READY(); // 0x769ab5b4
    error ZERO_TOTAL_REWARDS(); // 0xb113d2d4
    error EDIT_TIME_EXPIRED(); // 0x902feda5
    error ONLY_FUND_MANAGER(); // 0x65c9bc18
    error ALREADY_FUND_MANAGER(); // 0xd3fde4a5
    error NOT_FUND_MANAGER(); // 0xdcb9119d
    error ZERO_ADDRESS(); // 0x538ba4f9

    // =============================================================
    //                          Structs
    // =============================================================

    struct RewardScheduleStruct {
        uint256 totalRewards;
        uint256 createdTime;
    }

    // =============================================================
    //                   State Variables
    // =============================================================

    // reward schedule
    mapping(uint256 => RewardScheduleStruct) public rewardSchedule;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // the reward token should be USDC
    IERC20 public immutable rewardToken;

    // veFCTR token
    IVotingEscrow public immutable votingEscrow;

    uint256 public immutable editTime;

    mapping(address => bool) public fundManagers;

    // =============================================================
    //                      Functions
    // =============================================================

    constructor(uint256 _editTime, address _votingEscrow, address _rewardToken) {
        editTime = _editTime;
        votingEscrow = IVotingEscrow(_votingEscrow);
        rewardToken = IERC20(_rewardToken);
    }

    // claim reward based on veFCTR proportion in the multiple schedules
    function claimRewards(uint256[] memory blockNumberRewardSchedules) external nonReentrant {
        uint256[] memory rewardAmounts = new uint256[](blockNumberRewardSchedules.length);

        uint256 totalRewardAmount = 0;

        for (uint256 i = 0; i < blockNumberRewardSchedules.length; ) {
            uint256 blockNumberRewardSchedule = blockNumberRewardSchedules[i];

            // can't claim if has claimed
            if (hasClaimed[blockNumberRewardSchedule][msg.sender] == true) revert HAS_CLAIMED();

            // reward schedule must exists
            if (rewardSchedule[blockNumberRewardSchedule].createdTime == 0) revert INVALID_REWARD_SCHEDULE();

            // must after editTime
            if (rewardSchedule[blockNumberRewardSchedule].createdTime + editTime > block.timestamp)
                revert REWARD_CLAIM_NOT_READY();

            uint256 rewardAmount = calculateReward(msg.sender, blockNumberRewardSchedules[i]);

            hasClaimed[blockNumberRewardSchedule][msg.sender] = true;
            totalRewardAmount += rewardAmount;
            rewardAmounts[i] = rewardAmount;

            unchecked {
                i++;
            }
        }

        rewardToken.safeTransfer(msg.sender, totalRewardAmount);

        emit RewardClaimed(msg.sender, blockNumberRewardSchedules, rewardAmounts);
    }

    function calculateReward(address account, uint256 blockNumberRewardSchedule) public view returns (uint256) {
        // totalRewards * balance / totalSupply * marginOfError
        // margin of error 0.001% so adding 0.001%
        // why MoE? because some precision issue, the total balanceOf != totalSupply in veFCTR
        return
            (rewardSchedule[blockNumberRewardSchedule].totalRewards *
                votingEscrow.balanceOfAt(account, blockNumberRewardSchedule)) /
            (((votingEscrow.totalSupplyAt(blockNumberRewardSchedule) * 100001) / 100000));
    }

    function createRewardSchedule(uint256 totalRewards) external onlyFundManager returns (uint256) {
        // reward schedule must exists
        if (rewardSchedule[block.number].createdTime != 0) revert REWARD_SCHEDULE_EXIST();

        // total reward can't zero
        if (totalRewards == 0) revert ZERO_TOTAL_REWARDS();

        rewardSchedule[block.number].totalRewards = totalRewards;
        rewardSchedule[block.number].createdTime = block.timestamp;

        rewardToken.safeTransferFrom(msg.sender, address(this), totalRewards);

        emit RewardScheduleCreated(block.number, totalRewards, block.timestamp);

        return block.number;
    }

    // reward schedule can only be edited within editTime
    function editRewardSchedule(
        uint256 blockNumberRewardSchedule,
        uint256 totalRewards
    ) external nonReentrant onlyFundManager {
        // reward schedule must exists
        if (rewardSchedule[blockNumberRewardSchedule].createdTime == 0) revert INVALID_REWARD_SCHEDULE();

        // total reward can't zero
        if (totalRewards == 0) revert ZERO_TOTAL_REWARDS();

        // can only edit in edit time period
        if (rewardSchedule[blockNumberRewardSchedule].createdTime + editTime < block.timestamp)
            revert EDIT_TIME_EXPIRED();

        uint256 oldTotalRewards = rewardSchedule[blockNumberRewardSchedule].totalRewards;

        rewardSchedule[blockNumberRewardSchedule].totalRewards = totalRewards;

        // send back total rewards to the owner
        rewardToken.safeTransfer(msg.sender, oldTotalRewards);

        // send total rewards to the contract
        rewardToken.safeTransferFrom(msg.sender, address(this), totalRewards);

        emit RewardScheduleEdited(blockNumberRewardSchedule, oldTotalRewards, totalRewards);
    }

    // reward schedule can only be deleted within editTime
    function deleteRewardSchedule(uint256 blockNumberRewardSchedule) external nonReentrant onlyFundManager {
        // reward schedule must exists
        if (rewardSchedule[blockNumberRewardSchedule].createdTime == 0) revert INVALID_REWARD_SCHEDULE();

        // can only edit in edit time period
        if (rewardSchedule[blockNumberRewardSchedule].createdTime + editTime < block.timestamp)
            revert EDIT_TIME_EXPIRED();

        uint256 totalRewards = rewardSchedule[blockNumberRewardSchedule].totalRewards;

        // delete reward schedule
        delete rewardSchedule[blockNumberRewardSchedule];

        rewardToken.safeTransfer(msg.sender, totalRewards);

        emit RewardScheduleDeleted(blockNumberRewardSchedule);
    }

    // =============================================================
    //                     Fund Managers
    // =============================================================

    function addFundManager(address account) external onlyOwner {
        if (account == address(0)) revert ZERO_ADDRESS();
        if (fundManagers[account]) revert ALREADY_FUND_MANAGER();

        fundManagers[account] = true;

        emit FundManagerAdded(account);
    }

    function removeFundManager(address account) external onlyOwner {
        if (account == address(0)) revert ZERO_ADDRESS();
        if (!fundManagers[account]) revert NOT_FUND_MANAGER();

        fundManagers[account] = false;

        emit FundManagerRemoved(account);
    }

    // =============================================================
    //                      Modifier
    // =============================================================

    modifier onlyFundManager() {
        if (!fundManagers[msg.sender]) revert ONLY_FUND_MANAGER();
        _;
    }
}

