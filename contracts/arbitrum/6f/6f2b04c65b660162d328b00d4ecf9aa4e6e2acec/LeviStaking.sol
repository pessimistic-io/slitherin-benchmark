//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

error NotInitialized();
error AlreadyInitialized();
error StakingNotFound();

contract LeviStaking is Ownable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 stakingBalance;
        uint256 userAccumulator;
    }

    address public immutable LEVI_TOKEN;
    uint256 public immutable REWARDS_PER_SECOND;

    uint256 public accumulator;
    uint256 public lastUpdate;
    uint256 public totalStaked;

    bool initialized;

    mapping(address => UserInfo) public stakingDetails;

    event Staked(address account, uint256 amount);
    event StakedWithdrawed(address account, uint256 amount);

    constructor(address token) {
        LEVI_TOKEN = token;
        uint256 rewardsPerDay = 300 ether; /// 9k levi month
        REWARDS_PER_SECOND = rewardsPerDay / 86400;
    }

    function InitializeStaking(uint256 initialDeposit) external onlyOwner {
        if (initialized) revert AlreadyInitialized();

        initialized = true;

        uint256 rewards = 9000 ether;

        IERC20(LEVI_TOKEN).safeTransferFrom(msg.sender, address(this), rewards);

        stake(initialDeposit);
    }

    function stake(uint256 amount) public {
        if (!initialized) revert NotInitialized();

        uint256 userRewards = calculateReward(msg.sender);

        accumulator = getNewAccumulator();
        lastUpdate = block.timestamp;

        UserInfo storage userInfo = stakingDetails[msg.sender];

        userInfo.stakingBalance += amount;
        userInfo.userAccumulator = accumulator;

        if (userRewards > 0) {
            IERC20(LEVI_TOKEN).safeTransfer(msg.sender, userRewards);
        }

        totalStaked += amount;

        IERC20(LEVI_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function claimRewards() public {
        UserInfo storage userInfo = stakingDetails[msg.sender];
        if (userInfo.stakingBalance <= 0) revert StakingNotFound();

        uint256 userRewards = calculateReward(msg.sender);

        accumulator = getNewAccumulator();
        lastUpdate = block.timestamp;
        userInfo.userAccumulator = accumulator;

        if (userRewards > 0) {
            IERC20(LEVI_TOKEN).safeTransfer(msg.sender, userRewards);
        }
    }

    function withdrawStaked() external {
        UserInfo storage userInfo = stakingDetails[msg.sender];
        uint256 stakingBalance = userInfo.stakingBalance;

        if (stakingBalance <= 0) revert StakingNotFound();

        uint256 userRewards = calculateReward(msg.sender);

        if (userRewards > 0) {
            IERC20(LEVI_TOKEN).safeTransfer(msg.sender, userRewards);
        }

        userInfo.stakingBalance = 0;
        IERC20(LEVI_TOKEN).safeTransfer(msg.sender, stakingBalance);
        totalStaked -= stakingBalance;

        emit StakedWithdrawed(msg.sender, stakingBalance);
    }

    function getNewAccumulator() internal view returns (uint256) {
        if (totalStaked == 0) {
            return 0;
        } else {
            uint256 numerator = REWARDS_PER_SECOND *
                (block.timestamp - lastUpdate) *
                1e24;

            uint256 tokensPerStaked = numerator / totalStaked;
            return accumulator + tokensPerStaked;
        }
    }

    function calculateReward(address account) public view returns (uint256) {
        UserInfo memory userInfo = stakingDetails[account];

        uint256 stakedBalance = userInfo.stakingBalance;
        uint256 _userAccumulator = userInfo.userAccumulator;

        return ((stakedBalance * (getNewAccumulator() - _userAccumulator)) /
            1e24);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = IERC20(LEVI_TOKEN).balanceOf(address(this));
        IERC20(LEVI_TOKEN).safeTransfer(msg.sender, balance);
    }
}

