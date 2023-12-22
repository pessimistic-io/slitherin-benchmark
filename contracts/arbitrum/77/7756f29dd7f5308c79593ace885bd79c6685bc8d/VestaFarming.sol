// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";

//// Modified version of https://github.com/Synthetixio/Unipool/blob/master/contracts/Unipool.sol
contract VestaFarming is OwnableUpgradeable {
	using SafeMathUpgradeable for uint256;
	using SafeERC20Upgradeable for IERC20Upgradeable;

	event RewardAdded(uint256 reward);
	event Staked(address indexed user, uint256 amount);
	event Withdrawn(address indexed user, uint256 amount);
	event RewardPaid(address indexed user, uint256 reward);
	event EmergencyWithdraw(uint256 totalWithdrawn);

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

	modifier cannotBeZero(uint256 amount) {
		require(amount > 0, "Amount cannot be Zero");
		_;
	}

	function setUp(
		address _stakingToken,
		address _vsta,
		uint256 _weeklyDistribution,
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
		changeRewardDistribution(_weeklyDistribution);
		transferOwnership(_admin);
	}

	function lastTimeRewardApplicable() public view returns (uint256) {
		uint256 vstaBalance = vsta.balanceOf(address(this));
		if (
			vstaBalance == 0 ||
			rewardPerTokenStored.mul(oldTotalStaked).div(1e18) >= vstaBalance
		) {
			return lastUpdateTime;
		}

		return block.timestamp;
	}

	function rewardPerToken() public view returns (uint256) {
		if (totalStaked == 0) {
			return rewardPerTokenStored;
		}
		return
			rewardPerTokenStored.add(
				lastTimeRewardApplicable()
					.sub(lastUpdateTime)
					.mul(rewardRate)
					.mul(1e18)
					.div(totalStaked)
			);
	}

	function stake(uint256 amount) public cannotBeZero(amount) {
		updateReward(msg.sender);

		totalStaked = totalStaked.add(amount);
		balances[msg.sender] = balances[msg.sender].add(amount);
		stakingToken.safeTransferFrom(msg.sender, address(this), amount);

		emit Staked(msg.sender, amount);
	}

	function withdraw(uint256 amount) public cannotBeZero(amount) {
		require(amount <= balances[msg.sender], "Not enough staked");
		updateReward(msg.sender);

		totalStaked = totalStaked.sub(amount);
		balances[msg.sender] = balances[msg.sender].sub(amount);
		stakingToken.safeTransfer(msg.sender, amount);

		emit Withdrawn(msg.sender, amount);
	}

	function exit() public {
		withdraw(balances[msg.sender]);
		getReward();
	}

	function getReward() public {
		updateReward(msg.sender);
		uint256 reward = earned(msg.sender);

		if (reward > 0) {
			uint256 vstaBalance = vsta.balanceOf(address(this));
			rewards[msg.sender] = 0;

			if (reward > vstaBalance) reward = vstaBalance;

			vsta.safeTransfer(msg.sender, reward);

			emit RewardPaid(msg.sender, reward);
		}
	}

	function changeRewardDistribution(uint256 reward) public onlyOwner {
		updateReward(address(0));

		rewardRate = reward.div(DURATION);
		lastUpdateTime = lastTimeRewardApplicable();
		emit RewardAdded(reward);
	}

	function addFundToPool(uint256 _supply)
		public
		onlyOwner
		cannotBeZero(_supply)
	{
		vsta.safeTransferFrom(msg.sender, address(this), _supply);
		lastUpdateTime = lastTimeRewardApplicable();
		rewardPerTokenStored = rewardPerToken();
	}

	function updateReward(address account) public {
		rewardPerTokenStored = rewardPerToken();
		lastUpdateTime = lastTimeRewardApplicable();
		oldTotalStaked = totalStaked;

		if (account != address(0)) {
			rewards[account] = earned(account);
			userRewardPerTokenPaid[account] = rewardPerTokenStored;
		}
	}

	function earned(address account) public view returns (uint256) {
		return
			balances[account]
				.mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
				.div(1e18)
				.add(rewards[account]);
	}

	function emergencyWithdraw() public onlyOwner {
		uint256 totalSupply = vsta.balanceOf(address(this));
		vsta.safeTransfer(msg.sender, totalSupply);
		emit EmergencyWithdraw(totalSupply);
	}
}

