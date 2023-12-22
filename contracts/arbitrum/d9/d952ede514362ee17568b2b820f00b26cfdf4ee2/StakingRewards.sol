// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.7.6;

import "./Ownable.sol";
import "./Math.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

/// @title Complicated staking contract
/// @author Monty C. Python
contract StakingRewards is Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	/* ========== CONSTANTS ========== */

	uint256 public constant AMOUNT_MULTIPLIER = 1e4;
	uint256 public constant INIT_MULTIPLIER_VALUE = 1e30;
	uint8 public constant VESTING_CONST = 1e1;
	uint256 public constant ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;

	/* ========== STATE VARIABLES ========== */

	IERC20 public immutable stakingToken;
	IERC20 public immutable rewardsToken;

	uint256 public tokenPeriodFinish; // finish of tokens earning
	uint256 public tokenRewardRate; // how many tokens are given to pool every second
	uint256 public tokenRewardsDuration = 50;

	uint256 public nativePeriodFinish;
	uint256 public nativeRewardRate;
	uint256 public nativeRewardsDuration = 60 days;

	uint256 public lastNativeUpdateTime;
	uint256 public lastTokenUpdateTime;

	struct UserVariables {
		uint256 userTokenMultiplierPaid;
		uint256 userNativeMultiplierPaid;
		uint256 userLastUpdateTime;
		uint256 balanceLP;
		uint256 balanceST;
		uint256 balanceBP;
		uint256 balanceNC;
		uint256 balanceVST;
		uint256 balanceVSTStored;
		uint256 rewards;
		uint256 vestingFinishTime;
	}

	mapping(address => UserVariables) public userVariables;

	uint256 public _totalSupplyLP;
	uint256 public _totalSupplyBP;
	uint256 public _totalSupplyST;

	uint256 public nativeMultiplierStored = INIT_MULTIPLIER_VALUE;
	uint256 public tokenMultiplierStored = 0;

	/* ========== CONSTRUCTOR ========== */

	constructor(address _rewardsDistribution, address _rewardsToken, address _stakingToken) {
		rewardsToken = IERC20(_rewardsToken);
		stakingToken = IERC20(_stakingToken);
		transferOwnership(_rewardsDistribution);
	}

	/* ========== VIEWS FOR EXTERNAL USE ========== */

	function balanceBPOf(address account) external view returns (uint256) {
		return userVariables[account].balanceBP / AMOUNT_MULTIPLIER;
	}

	function balanceLPOf(address account) external view returns (uint256) {
		return userVariables[account].balanceLP / AMOUNT_MULTIPLIER;
	}

	function balanceSTOf(address account) external view returns (uint256) {
		return userVariables[account].balanceST / AMOUNT_MULTIPLIER;
	}

	function totalSupplyLP() external view returns (uint256) {
		return _totalSupplyLP / AMOUNT_MULTIPLIER;
	}

	function totalSupplyBP() external view returns (uint256) {
		return _totalSupplyBP / AMOUNT_MULTIPLIER;
	}

	function totalSupplyST() external view returns (uint256) {
		return _totalSupplyST / AMOUNT_MULTIPLIER;
	}

	/* ========== VIEWS FOR CONTRACT ========== */

	function lastTimeTokenRewardApplicable() public view returns (uint256) {
		return Math.min(block.timestamp, tokenPeriodFinish);
	}

	function lastTimeNativeRewardApplicable() public view returns (uint256) {
		return Math.min(block.timestamp, nativePeriodFinish);
	}

	function getNativeMultiplier() public view returns (uint256) {
		if (_totalSupplyLP + _totalSupplyST + _totalSupplyBP == 0) {
			return nativeMultiplierStored;
		}

		uint256 timeDiff = lastTimeNativeRewardApplicable() - lastNativeUpdateTime;
		uint256 totalShares = _totalSupplyLP + _totalSupplyBP + _totalSupplyST;

		return nativeMultiplierStored + (nativeMultiplierStored * timeDiff * nativeRewardRate) / totalShares;
	}

	function getTokenMultiplier() public view returns (uint256) {
		if (_totalSupplyLP + _totalSupplyST + _totalSupplyBP == 0) {
			return tokenMultiplierStored;
		}

		uint256 timeDiff = lastTimeTokenRewardApplicable() - lastTokenUpdateTime;
		uint256 totalShares = _totalSupplyLP + _totalSupplyBP + _totalSupplyST;

		return tokenMultiplierStored + (nativeMultiplierStored * timeDiff * tokenRewardRate) / totalShares;
	}

	function tokenEarned(address account) internal view returns (uint256) {
		UserVariables storage variables = userVariables[account];

		uint256 userShares = variables.balanceLP + variables.balanceBP + variables.balanceST;
		uint256 multiplierDiff = getTokenMultiplier() - variables.userTokenMultiplierPaid;
		uint256 divider = Math.max(variables.userNativeMultiplierPaid, INIT_MULTIPLIER_VALUE);

		return (userShares * multiplierDiff) / divider;
	}

	function nativeEarned(address account) internal view returns (uint256) {
		UserVariables storage variables = userVariables[account];

		uint256 userShares = variables.balanceLP + variables.balanceBP + variables.balanceST;

		uint256 multiplierDiff = getNativeMultiplier();

		uint256 divider = Math.max(variables.userNativeMultiplierPaid, INIT_MULTIPLIER_VALUE);

		return (userShares * multiplierDiff) / divider;
	}

	/* ========== MUTATIVE FUNCTIONS ========== */

	function stakeFor(uint256 amount, address receiver) external nonReentrant updateReward(receiver) {
		require(amount != 0, 'Cannot stake 0');

		stakingToken.safeTransferFrom(msg.sender, address(this), amount);

		amount *= AMOUNT_MULTIPLIER;
		userVariables[receiver].balanceLP += amount;
		_totalSupplyLP += amount;

		emit Staked(receiver, amount / AMOUNT_MULTIPLIER);
	}

	function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
		require(amount != 0, 'Cannot stake 0');

		stakingToken.safeTransferFrom(msg.sender, address(this), amount);

		amount *= AMOUNT_MULTIPLIER;
		userVariables[msg.sender].balanceLP += amount;
		_totalSupplyLP += amount;

		emit Staked(msg.sender, amount / AMOUNT_MULTIPLIER);
	}

	function getNativeReward() public nonReentrant updateReward(msg.sender) {
		UserVariables storage variables = userVariables[msg.sender];

		uint256 reward = variables.balanceNC;

		if (reward > 0) {
			variables.balanceNC = 0;

			(bool sent, ) = msg.sender.call{value: reward / AMOUNT_MULTIPLIER}('');

			require(sent, 'Native transfer failed');

			emit NativeRewardPaid(msg.sender, reward / AMOUNT_MULTIPLIER);
		}
	}

	function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
		require(amount != 0, 'Cannot withdraw 0');

		UserVariables storage variables = userVariables[msg.sender];

		variables.balanceLP -= amount * AMOUNT_MULTIPLIER;
		_totalSupplyLP -= amount * AMOUNT_MULTIPLIER;

		_totalSupplyBP -= variables.balanceBP;
		variables.balanceBP = 0;

		stakingToken.safeTransfer(msg.sender, amount);

		emit Withdrawn(msg.sender, amount);
	}

	function getReward() public nonReentrant updateReward(msg.sender) {
		uint256 reward = userVariables[msg.sender].rewards;

		if (reward > 0) {
			userVariables[msg.sender].rewards = 0;

			rewardsToken.safeTransfer(msg.sender, reward / AMOUNT_MULTIPLIER);
			emit TokenRewardPaid(msg.sender, reward / AMOUNT_MULTIPLIER);
		}
	}

	/// @notice if user call this function, his vesting period going to reset
	function vest(uint amount) public nonReentrant updateReward(msg.sender) {
		amount *= AMOUNT_MULTIPLIER;

		require(amount != 0, 'Cannot vest 0');

		UserVariables storage variables = userVariables[msg.sender];
		uint256 balance = variables.balanceST;

		require(amount <= balance, 'Cannot vest more then balance');
		require(amount * VESTING_CONST <= variables.balanceLP, 'You should have more staked LP tokens');

		variables.balanceST -= amount;
		_totalSupplyST -= amount;

		variables.balanceVST -= variables.balanceVSTStored;
		variables.balanceVST += amount;

		variables.vestingFinishTime = block.timestamp + ONE_YEAR_IN_SECS;

		emit Vesting(msg.sender, amount / AMOUNT_MULTIPLIER);
	}

	function compoundBP() external updateReward(msg.sender) {}

	/// @notice returns data about user rewards for front-end, supposed to be called via staticCall
	function getUserData() external updateReward(msg.sender) returns (uint256, uint256, uint256, uint256, uint256) {
		UserVariables storage userCurrentVariables = userVariables[msg.sender];

		return (
			userCurrentVariables.balanceLP / AMOUNT_MULTIPLIER,
			userCurrentVariables.balanceBP / AMOUNT_MULTIPLIER,
			userCurrentVariables.balanceNC / AMOUNT_MULTIPLIER,
			userCurrentVariables.balanceST / AMOUNT_MULTIPLIER,
			userCurrentVariables.balanceVST / AMOUNT_MULTIPLIER
		);
	}

	function exit() external {
		withdraw(userVariables[msg.sender].balanceLP / AMOUNT_MULTIPLIER);
		getReward();
	}

	/* ========== RESTRICTED FUNCTIONS ========== */

	function notifyTokenRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
		if (block.timestamp >= tokenPeriodFinish) {
			tokenRewardRate = (reward * AMOUNT_MULTIPLIER) / tokenRewardsDuration;
		} else {
			uint256 remaining = tokenPeriodFinish - block.timestamp;
			uint256 leftover = remaining * tokenRewardRate;
			tokenRewardRate = (reward * AMOUNT_MULTIPLIER + leftover) / tokenRewardsDuration;
		}

		uint balance = rewardsToken.balanceOf(address(this));
		require(tokenRewardRate <= (balance * AMOUNT_MULTIPLIER) / tokenRewardsDuration, 'Provided reward too high');

		lastTokenUpdateTime = block.timestamp;

		tokenPeriodFinish = block.timestamp + tokenRewardsDuration;
		emit TokenRewardAdded(reward);
	}

	function notifyNativeRewardAmount(uint256 amount) external payable onlyOwner updateReward(address(0)) {
		if (block.timestamp >= nativePeriodFinish) {
			nativeRewardRate = (amount * AMOUNT_MULTIPLIER) / nativeRewardsDuration;
		} else {
			uint256 remaining = nativePeriodFinish - block.timestamp;
			uint256 leftover = remaining * nativeRewardRate;
			nativeRewardRate = (amount * AMOUNT_MULTIPLIER + leftover) / nativeRewardsDuration;
		}

		uint balance = address(this).balance;
		require(nativeRewardRate <= (balance * AMOUNT_MULTIPLIER) / nativeRewardsDuration, 'Provided reward too high');

		lastNativeUpdateTime = block.timestamp;
		nativePeriodFinish = block.timestamp + nativeRewardsDuration;
		emit NativeRewardAdded(amount);
	}

	/* ========== MODIFIERS ========== */

	modifier updateReward(address account) {
		UserVariables storage variables = userVariables[account];

		updateStoredVariables();

		uint256 _lastTimeNativeRewardApplicable = lastTimeNativeRewardApplicable();

		if (_totalSupplyLP != 0) {
			_totalSupplyST +=
				(lastTimeNativeRewardApplicable() - Math.min(lastTimeNativeRewardApplicable(), lastNativeUpdateTime)) *
				nativeRewardRate;
		}

		lastNativeUpdateTime = _lastTimeNativeRewardApplicable;
		lastTokenUpdateTime = lastTimeTokenRewardApplicable();

		if (account != address(0)) {
			updateUserVariables(account);

			updateBonusPoints(account);
			updateVesting(account);

			variables.userLastUpdateTime = block.timestamp;
		}

		_;
	}

	function updateUserVariables(address account) internal {
		UserVariables storage variables = userVariables[account];

		variables.rewards += tokenEarned(account);
		variables.balanceST = nativeEarned(account) - variables.balanceLP - variables.balanceBP;

		variables.userTokenMultiplierPaid = tokenMultiplierStored;
		variables.userNativeMultiplierPaid = nativeMultiplierStored;
	}

	function updateStoredVariables() internal {
		tokenMultiplierStored = getTokenMultiplier();
		nativeMultiplierStored = getNativeMultiplier();
	}

	function updateBonusPoints(address account) internal {
		UserVariables storage variables = userVariables[account];

		if (userVariables[account].userLastUpdateTime == 0) return;

		uint256 increaseOfBP = ((block.timestamp - userVariables[account].userLastUpdateTime) * variables.balanceLP) /
			ONE_YEAR_IN_SECS;

		_totalSupplyBP += increaseOfBP;
		variables.balanceBP += increaseOfBP;
	}

	function updateVesting(address account) internal {
		UserVariables storage variables = userVariables[account];

		if (
			Math.min(block.timestamp, userVariables[account].vestingFinishTime) <
			userVariables[account].userLastUpdateTime
		) {
			return;
		}

		uint256 increaseOfNC = ((Math.min(block.timestamp, variables.vestingFinishTime) -
			variables.userLastUpdateTime) *
			Math.min(userVariables[account].balanceVST, variables.balanceLP / VESTING_CONST)) / ONE_YEAR_IN_SECS;

		variables.balanceNC += increaseOfNC;
		variables.balanceVSTStored += increaseOfNC;
	}

	/* ========== EVENTS ========== */

	event TokenRewardAdded(uint256 reward);
	event NativeRewardAdded(uint256 reward);
	event Staked(address indexed user, uint256 amount);
	event Withdrawn(address indexed user, uint256 amount);
	event TokenRewardPaid(address indexed user, uint256 reward);
	event NativeRewardPaid(address indexed user, uint256 reward);
	event Vesting(address indexed user, uint256 reward);
}
