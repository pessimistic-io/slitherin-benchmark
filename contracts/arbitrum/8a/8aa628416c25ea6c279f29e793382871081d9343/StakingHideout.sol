// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ICounterfeitMoney.sol";
import "./IStakingHideout.sol";
import "./IStolenNFT.sol";
import "./EnumerableEscrow.sol";

error NotTheStaker();
error NotTheTokenOwner();
error StashIsFull();
error TokenNotStashed();

/// @title A place to hide your stolen NFTs and earn some Counterfeit Money to bribe the police
/// @dev based on [Synthetix StakingRewards](https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol)
contract StakingHideout is IStakingHideout, EnumerableEscrow, Ownable {
	/// Maximum number of NFTs that can be staked per thief
	uint256 public balanceLimit = 5;
	/// The staking reward rate, default 100000eth/day = 100000/(60*60*24) = 1.1574074074
	uint256 public rewardRate = 1157407407407407407;
	/// Timestamp of the last time the calculations were run
	uint256 public lastUpdateTime;
	/// Stored reward rate for a staked token
	uint256 public rewardPerTokenStored;

	/// Amount of staker's rewards per token since the last update
	mapping(address => uint256) public userRewardPerTokenPaid;
	/// Amount of rewards earned by a staker that can be withdrawn
	mapping(address => uint256) public rewards;

	/// IERC721 token used to stake and earn rewards with
	IStolenNFT public stakingNft;
	/// IERC20 token used to pay rewards
	ICounterfeitMoney public rewardsToken;

	/// Mapping from a staked token to its staker
	mapping(uint256 => address) private _stakers;

	constructor(
		address _owner,
		address _stakingNft,
		address _rewardsToken
	) Ownable(_owner) {
		stakingNft = IStolenNFT(_stakingNft);
		rewardsToken = ICounterfeitMoney(_rewardsToken);
	}

	/// @inheritdoc IStakingHideout
	function stash(uint256 tokenId) public override updateReward(msg.sender) {
		if (stakingNft.ownerOf(tokenId) != msg.sender) revert NotTheTokenOwner();
		if (EnumerableEscrow.balanceOf(msg.sender) >= balanceLimit) revert StashIsFull();

		EnumerableEscrow._addTokenToEnumeration(msg.sender, tokenId);
		_stakers[tokenId] = msg.sender;

		emit Stashed(msg.sender, tokenId);

		stakingNft.transferFrom(msg.sender, address(this), tokenId);
	}

	/// @inheritdoc IStakingHideout
	function stashWithPermit(
		uint256 tokenId,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external override {
		stakingNft.permit(msg.sender, address(this), tokenId, deadline, v, r, s);
		stash(tokenId);
	}

	/// @inheritdoc IStakingHideout
	function unstash(uint256 tokenId) external override updateReward(_stakers[tokenId]) {
		address staker = _stakers[tokenId];
		if (msg.sender != staker && msg.sender != Ownable.owner()) revert NotTheStaker();

		EnumerableEscrow._removeTokenFromEnumeration(staker, tokenId);
		delete _stakers[tokenId];

		emit Unstashed(staker, tokenId);

		stakingNft.transferFrom(address(this), staker, tokenId);
	}

	/// @notice Sets and updates the staking reward rate
	/// @dev Can only be called by the contract owner a RewardRateChange event
	/// @param _rewardRate The rate to be set
	function setRewardRate(uint256 _rewardRate) external onlyOwner updateReward(address(0)) {
		rewardRate = _rewardRate;
		emit RewardRateChange(_rewardRate);
	}

	/// @notice Sets the maximum number of NFTs that can be staked per thief
	/// @dev Can only be called by the contract owner and emits a BalanceLimitChange event
	/// @param _balanceLimit The maximum stash size for a thief
	function setBalanceLimit(uint256 _balanceLimit) external onlyOwner {
		balanceLimit = _balanceLimit;
		emit BalanceLimitChange(_balanceLimit);
	}

	/// @inheritdoc IStakingHideout
	function getStaker(uint256 tokenId) external view override returns (address) {
		if (_stakers[tokenId] == address(0)) revert TokenNotStashed();
		return _stakers[tokenId];
	}

	/// @inheritdoc IStakingHideout
	function getReward() external override updateReward(msg.sender) {
		uint256 reward = rewards[msg.sender];
		emit RewardPaid(msg.sender, reward);
		if (reward > 0) {
			rewards[msg.sender] = 0;
			rewardsToken.print(msg.sender, reward);
		}
	}

	/// @inheritdoc IStakingHideout
	function rewardPerToken() public view override returns (uint256) {
		if (EnumerableEscrow.totalSupply() == 0) {
			return rewardPerTokenStored;
		}

		return
			rewardPerTokenStored +
			(((block.timestamp - lastUpdateTime) * rewardRate * 1e18) /
				EnumerableEscrow.totalSupply());
	}

	/// @inheritdoc IStakingHideout
	function earned(address account) public view override returns (uint256) {
		return
			((EnumerableEscrow.balanceOf(account) *
				(rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
	}

	/// @dev Tracks the rewards earned for a user per token
	modifier updateReward(address account) {
		rewardPerTokenStored = rewardPerToken();
		lastUpdateTime = block.timestamp;
		if (account != address(0)) {
			rewards[account] = earned(account);
			userRewardPerTokenPaid[account] = rewardPerTokenStored;
		}
		_;
	}

	/// @notice Emitted when the reward rate changes
	/// @param newRewardRate The new reward rate
	event RewardRateChange(uint256 newRewardRate);

	/// @notice Emitted when the balance limit changes
	/// @param newBalanceLimit The new balance limit
	event BalanceLimitChange(uint256 newBalanceLimit);
}

