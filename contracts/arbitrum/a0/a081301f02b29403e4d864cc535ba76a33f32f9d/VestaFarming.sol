// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";

import "./FullMath.sol";

import "./IVestaFarming.sol";

import "./MissingRewards.sol";

//// Modified version of https://github.com/Synthetixio/Unipool/blob/master/contracts/Unipool.sol
contract VestaFarming is IVestaFarming, OwnableUpgradeable {
	using SafeMathUpgradeable for uint256;
	using SafeERC20Upgradeable for IERC20Upgradeable;

	uint256 public constant DURATION = 1 weeks;

	IERC20Upgradeable public stakingToken;
	IERC20Upgradeable public vsta;

	uint256 public totalStaked;
	uint256 public oldTotalStaked;

	uint256 public rewardRate;
	uint256 public rewardPerTokenStored;
	uint256 public lastUpdateTime;

	mapping(address => uint256) public balances;
	mapping(address => uint256) public userRewardPerTokenPaid;
	mapping(address => uint256) public rewards;

	uint256 public totalSupply;

	uint64 public periodFinish;
	uint256 internal constant PRECISION = 1e30;
	uint64 public constant MONTHLY_DURATION = 2628000;

	MissingRewards public missingRewards;

	modifier cannotBeZero(uint256 amount) {
		require(amount > 0, "Amount cannot be Zero");
		_;
	}

	function setUp(
		address _stakingToken,
		address _vsta,
		uint256, /*_weeklyDistribution*/
		address _admin
	) external initializer {
		require(
			address(_stakingToken) != address(0),
			"Staking Token Cannot be zero!"
		);
		require(address(_vsta) != address(0), "VSTA Cannot be zero!");
		__Ownable_init();

		stakingToken = IERC20Upgradeable(_stakingToken);
		vsta = IERC20Upgradeable(_vsta);

		lastUpdateTime = block.timestamp;
		transferOwnership(_admin);
	}

	function setMissingRewards(address _missingReward) external onlyOwner {
		missingRewards = MissingRewards(_missingReward);
	}

	function stake(uint256 amount) external {
		if (amount == 0) return;

		uint256 accountBalance = balances[msg.sender];
		uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable();
		uint256 totalStake_ = totalStaked;
		uint256 rewardPerToken_ = _rewardPerToken(
			totalStake_,
			lastTimeRewardApplicable_,
			rewardRate
		);

		rewardPerTokenStored = rewardPerToken_;
		lastUpdateTime = lastTimeRewardApplicable_;
		rewards[msg.sender] = _earned(
			msg.sender,
			accountBalance,
			rewardPerToken_,
			rewards[msg.sender]
		);
		userRewardPerTokenPaid[msg.sender] = rewardPerToken_;

		totalStaked = totalStake_ + amount;
		balances[msg.sender] = accountBalance + amount;

		stakingToken.safeTransferFrom(msg.sender, address(this), amount);

		emit Staked(msg.sender, amount);
	}

	function withdraw(uint256 amount) public virtual {
		if (amount == 0) return;

		uint256 accountBalance = balances[msg.sender];
		uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable();
		uint256 totalStake_ = totalStaked;
		uint256 rewardPerToken_ = _rewardPerToken(
			totalStake_,
			lastTimeRewardApplicable_,
			rewardRate
		);

		rewardPerTokenStored = rewardPerToken_;
		lastUpdateTime = lastTimeRewardApplicable_;
		rewards[msg.sender] = _earned(
			msg.sender,
			accountBalance,
			rewardPerToken_,
			rewards[msg.sender]
		);
		userRewardPerTokenPaid[msg.sender] = rewardPerToken_;

		balances[msg.sender] = accountBalance - amount;

		totalStaked = totalStake_ - amount;

		stakingToken.safeTransfer(msg.sender, amount);

		emit Withdrawn(msg.sender, amount);
	}

	function exit() public virtual {
		uint256 accountBalance = balances[msg.sender];

		uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable();
		uint256 totalStake_ = totalStaked;
		uint256 rewardPerToken_ = _rewardPerToken(
			totalStake_,
			lastTimeRewardApplicable_,
			rewardRate
		);

		uint256 reward = _earned(
			msg.sender,
			accountBalance,
			rewardPerToken_,
			rewards[msg.sender]
		);
		if (reward > 0) {
			rewards[msg.sender] = 0;
		}

		rewardPerTokenStored = rewardPerToken_;
		lastUpdateTime = lastTimeRewardApplicable_;
		userRewardPerTokenPaid[msg.sender] = rewardPerToken_;

		balances[msg.sender] = 0;

		totalStaked = totalStake_ - accountBalance;

		stakingToken.safeTransfer(msg.sender, accountBalance);
		emit Withdrawn(msg.sender, accountBalance);

		if (reward > 0) {
			vsta.safeTransfer(msg.sender, reward);
			emit RewardPaid(msg.sender, reward);
		}
	}

	function getReward() public virtual {
		uint256 accountBalance = balances[msg.sender];
		uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable();
		uint256 totalStake_ = totalStaked;
		uint256 rewardPerToken_ = _rewardPerToken(
			totalStake_,
			lastTimeRewardApplicable_,
			rewardRate
		);

		uint256 reward = _earned(
			msg.sender,
			accountBalance,
			rewardPerToken_,
			rewards[msg.sender]
		);

		rewardPerTokenStored = rewardPerToken_;
		lastUpdateTime = lastTimeRewardApplicable_;
		userRewardPerTokenPaid[msg.sender] = rewardPerToken_;

		if (reward > 0) {
			missingRewards.eraseData(msg.sender);
			rewards[msg.sender] = 0;

			vsta.safeTransfer(msg.sender, reward);
			emit RewardPaid(msg.sender, reward);
		}
	}

	function lastTimeRewardApplicable() public view returns (uint64) {
		return
			block.timestamp < periodFinish
				? uint64(block.timestamp)
				: periodFinish;
	}

	function rewardPerToken() external view returns (uint256) {
		return
			_rewardPerToken(totalStaked, lastTimeRewardApplicable(), rewardRate);
	}

	function earned(address account) external view returns (uint256) {
		return
			_earned(
				account,
				balances[account],
				_rewardPerToken(
					totalStaked,
					lastTimeRewardApplicable(),
					rewardRate
				),
				rewards[account]
			);
	}

	/// @notice Lets a reward distributor start a new reward period. The reward tokens must have already
	/// been transferred to this contract before calling this function. If it is called
	/// when a reward period is still active, a new reward period will begin from the time
	/// of calling this function, using the leftover rewards from the old reward period plus
	/// the newly sent rewards as the reward.
	/// @dev If the reward amount will cause an overflow when computing rewardPerToken, then
	/// this function will revert.
	/// @param reward The amount of reward tokens to use in the new reward period.
	function notifyRewardAmount(uint256 reward) external onlyOwner {
		if (reward == 0) return;

		uint256 rewardRate_ = rewardRate;
		uint64 periodFinish_ = periodFinish;
		uint64 lastTimeRewardApplicable_ = block.timestamp < periodFinish_
			? uint64(block.timestamp)
			: periodFinish_;
		uint64 DURATION_ = MONTHLY_DURATION;
		uint256 totalStake_ = totalStaked;

		rewardPerTokenStored = _rewardPerToken(
			totalStake_,
			lastTimeRewardApplicable_,
			rewardRate_
		);
		lastUpdateTime = lastTimeRewardApplicable_;

		uint256 newRewardRate;
		if (block.timestamp >= periodFinish_) {
			newRewardRate = reward / DURATION_;
		} else {
			uint256 remaining = periodFinish_ - block.timestamp;
			uint256 leftover = remaining * rewardRate_;
			newRewardRate = (reward + leftover) / DURATION_;
		}

		if (newRewardRate >= ((type(uint256).max / PRECISION) / DURATION_)) {
			revert Error_AmountTooLarge();
		}

		rewardRate = newRewardRate;
		lastUpdateTime = uint64(block.timestamp);
		periodFinish = uint64(block.timestamp + DURATION_);

		emit RewardAdded(reward);
	}

	function _earned(
		address account,
		uint256 accountBalance,
		uint256 rewardPerToken_,
		uint256 accountRewards
	) internal view returns (uint256) {
		return
			FullMath.mulDiv(
				accountBalance,
				rewardPerToken_ - userRewardPerTokenPaid[account],
				PRECISION
			) +
			accountRewards +
			missingRewards.getMissingReward(account);
	}

	function _rewardPerToken(
		uint256 totalStake_,
		uint256 lastTimeRewardApplicable_,
		uint256 rewardRate_
	) internal view returns (uint256) {
		if (totalStake_ == 0) {
			return rewardPerTokenStored;
		}
		return
			rewardPerTokenStored +
			FullMath.mulDiv(
				(lastTimeRewardApplicable_ - lastUpdateTime) * PRECISION,
				rewardRate_,
				totalStake_
			);
	}

	function fixPool() external onlyOwner {
		periodFinish = uint64(block.timestamp);

		uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable();
		uint256 totalStake_ = totalStaked;
		uint256 rewardPerToken_ = _rewardPerToken(
			totalStake_,
			lastTimeRewardApplicable_,
			rewardRate
		);

		rewardPerTokenStored = rewardPerToken_;
		lastUpdateTime = lastTimeRewardApplicable_;

		totalSupply = 0;
		oldTotalStaked = 0;
	}
}

