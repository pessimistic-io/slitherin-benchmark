// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./SafeTransferLib.sol";
import "./FixedPointMathLib.sol";
import "./Ownership.sol";

contract Staking is Ownership {
	using SafeTransferLib for ERC20;
	using FixedPointMathLib for uint256;

	/// @notice staked tokens used as 'shares'
	ERC20 public immutable asset;
	/// @notice reward token
	ERC20 public immutable reward;

	/// @notice record of total distributed rewards per share, used to calculate rewards as users join/leave the pool
	/// @dev gradually increments. users will be updated to the current figure whenever they interact with the contract
	uint256 public totalRewardsPerShare;

	/// @notice period over which staked assets are gradually vested
	uint256 public lockDuration = 7 days;
	uint256 internal constant MAX_LOCK_DURATION = 28 days;

	/// @notice total shares staked in contract
	/// @dev used instead of asset.balanceOf(address(this)) to prevent direct transfers from diluting everyone's rewards
	uint256 public totalShares;

	/// @notice current balance of rewards in contract, used for reward calculations
	uint256 public currentRewardBalance;

	/// @dev multiple mappings cost slightly less gas than a single mapping to a struct with multiple variables

	/// @notice amount of shares (staked assets) per user
	mapping(address => uint256) public shares;
	/// @notice timestamp of the user's last deposit, used for vesting unlock calculations
	mapping(address => uint256) public lastDepositTimestamp;

	/// @dev record of user's last total rewards per share checkpoint
	mapping(address => uint256) private _indexOf;
	mapping(address => uint256) private _unclaimedRewards;
	mapping(address => uint256) private _lockedAssets;

	uint256 internal constant MULTIPLIER = 1e18;

	constructor(
		ERC20 _asset,
		ERC20 _reward,
		address _nominatedOwner,
		address _admin,
		address[] memory _authorized
	) Ownership(_nominatedOwner, _admin, _authorized) {
		asset = _asset;
		reward = _reward;
	}

	/*//////////////////////////
	/      View Functions      /
	//////////////////////////*/

	/// @notice amount of staked assets locked at the current timestamp
	function lockedAssets(address _account) public view returns (uint256) {
		uint256 locked = _lockedAssets[_account];
		if (locked == 0) return 0;

		uint256 duration = lockDuration;
		uint256 timestamp = lastDepositTimestamp[_account];

		if (block.timestamp >= timestamp + duration) return 0;
		return locked - locked.mulDivUp(block.timestamp - timestamp, duration);
	}

	/// @notice amount of staked assets user can withdraw at the current timestamp
	function freeAssets(address _account) public view returns (uint256) {
		return shares[_account] - lockedAssets(_account);
	}

	function unclaimedRewards(address _account) public view returns (uint256) {
		return _unclaimedRewards[_account] + _calculateRewards(_account);
	}

	/*//////////////////////////
	/      User Functions      /
	//////////////////////////*/

	event Deposit(address indexed account, uint256 assets);

	function deposit(uint256 _assets) external updateUser(msg.sender) {
		asset.safeTransferFrom(msg.sender, address(this), _assets);
		shares[msg.sender] += _assets;
		totalShares += _assets;

		uint256 locked = lockedAssets(msg.sender);

		// update user lock
		lastDepositTimestamp[msg.sender] = block.timestamp;
		_lockedAssets[msg.sender] = locked + _assets;

		emit Deposit(msg.sender, _assets);
	}

	error AssetsLocked();
	event Withdraw(address indexed account, uint256 assets);

	function withdraw(uint256 _assets) external updateUser(msg.sender) {
		if (_assets > freeAssets(msg.sender)) revert AssetsLocked();

		shares[msg.sender] -= _assets;
		totalShares -= _assets;
		asset.safeTransfer(msg.sender, _assets);

		emit Withdraw(msg.sender, _assets);
	}

	event ClaimedRewards(address indexed account, uint256 rewards);
	error NoRewardsToClaim();

	function claimRewards() external updateUser(msg.sender) returns (uint256 rewards) {
		rewards = _unclaimedRewards[msg.sender];
		if (rewards == 0) revert NoRewardsToClaim();

		_unclaimedRewards[msg.sender] = 0;
		reward.safeTransfer(msg.sender, rewards);
		currentRewardBalance -= rewards;

		emit ClaimedRewards(msg.sender, rewards);
	}

	/*////////////////////////////////
	/      Authorized Functions      /
	////////////////////////////////*/

	event RewardsAdded(uint256 rewards, uint256 rewardsPerShare, uint256 newTotalRewardsPerShare);

	error NoRewardsToUpdate();
	error NoShares();

	/// @dev authorize treasury contract to automatically call this during harvest
	function updateTotalRewards() external onlyAuthorized {
		if (totalShares == 0) revert NoShares();

		uint256 rewards = reward.balanceOf(address(this)) - currentRewardBalance;
		if (rewards == 0) revert NoRewardsToUpdate();

		uint256 rewardsPerShare = rewards.mulDivDown(MULTIPLIER, totalShares);

		currentRewardBalance += rewards;
		totalRewardsPerShare += rewardsPerShare;

		emit RewardsAdded(rewards, rewardsPerShare, totalRewardsPerShare);
	}

	/*///////////////////////////
	/      Admin Functions      /
	///////////////////////////*/

	event LockDurationSet(uint256 duration);
	error AboveMaximumLockDuration();

	function setLockDuration(uint256 _duration) external onlyAdmins {
		if (_duration > MAX_LOCK_DURATION) revert AboveMaximumLockDuration();
		lockDuration = _duration;

		emit LockDurationSet(_duration);
	}

	error NothingToSkim();

	/*///////////////////////////
	/      Owner Functions      /
	///////////////////////////*/

	/// @notice used to withdraw assets accidentally transferred into contract (users should use deposit function)
	function skim() external onlyOwner {
		uint256 amount = asset.balanceOf(address(this)) - totalShares;
		if (amount == 0) revert NothingToSkim();
		asset.safeTransfer(msg.sender, amount);
	}

	error InvalidToken();
	error NothingToSweep();

	/// @notice used to withdraw tokens accidentally transferred to this contract
	function sweep(ERC20 _token) external onlyOwner {
		if (_token == asset || _token == reward) revert InvalidToken();
		uint256 amount = _token.balanceOf(address(this));
		if (amount == 0) revert NothingToSweep();
		_token.safeTransfer(msg.sender, amount);
	}

	/*///////////////////////////
	/      Internal Logic       /
	///////////////////////////*/

	modifier updateUser(address _account) {
		uint256 rewards = _calculateRewards(_account);
		_indexOf[_account] = totalRewardsPerShare;
		_unclaimedRewards[_account] += rewards;
		_;
	}

	function _calculateRewards(address _account) private view returns (uint256 rewards) {
		uint256 userShares = shares[_account];
		if (userShares == 0) return 0;

		return (totalRewardsPerShare - _indexOf[_account]).mulDivDown(userShares, MULTIPLIER);
	}
}

