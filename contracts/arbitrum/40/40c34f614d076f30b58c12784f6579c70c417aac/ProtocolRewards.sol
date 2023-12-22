// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IERC721.sol";
import { IVotingEscrow } from "./IVotingEscrow.sol";
import { OwnableWithTransfer } from "./OwnableWithTransfer.sol";

// import "hardhat/console.sol";

/**
 * @title Implements a reward system which grant rewards based on veToken balance
 * at specific blocks.
 * @author flashloner
 */
contract ProtocolRewards is ReentrancyGuard, OwnableWithTransfer {
	using SafeERC20 for IERC20;

	struct Reward {
		uint256 blockNumber;
		uint256 amount;
	}

	// about 10 years worth of rewards
	// we don't allow adding reward rounds more frequently than 13 days
	uint256 public constant MAX_REWARDS = 280;

	/* ========== STATE VARIABLES ========== */

	address public rewardsToken;
	address public veToken; // address of the ve token
	uint256 public currentBalance; // running balance of rewards in contract
	uint256 public lastRewardTime;

	// manger role can add rewards
	address public manager;

	modifier onlyManager() {
		if (msg.sender != manager) revert OnlyManager();
		_;
	}

	Reward[] public rewards;
	mapping(address => uint256) public firstUnclaimedReward;

	constructor(
		address _veToken,
		address _manager,
		address _rewardsToken
	) OwnableWithTransfer(msg.sender) {
		rewardsToken = _rewardsToken;
		manager = _manager;
		veToken = _veToken;
	}

	/* ========== RESTRICTED FUNCTIONS ========== */

	function setManager(address _manager) external onlyOwner {
		manager = _manager;
	}

	/**
	 * @notice Add a reward distribution round
	 */
	function addRewardRound() external onlyManager {
		// compute the reward amount
		uint256 newBalance = IERC20(rewardsToken).balanceOf(address(this));
		uint256 reward = newBalance - currentBalance;
		if (reward == 0) revert NoRewardTokenBalance();

		// make sure we don't add rounds too often
		if (lastRewardTime + 13 days > block.timestamp) revert TooEarlyToAddReward();
		if (rewards.length == MAX_REWARDS) revert TooManyRewards();

		// ensure veToken is not empty
		if (IVotingEscrow(veToken).totalSupplyAt(block.number) == 0) revert VaultIsEmpty();

		rewards.push(Reward({ blockNumber: block.number, amount: reward }));

		currentBalance = newBalance;
		lastRewardTime = block.timestamp;

		emit RewardAdded(reward);
	}

	/**
	 * @notice Added to support to recover ERC20 token within a whitelist
	 */
	function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
		uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
		if (balance < tokenAmount)
			revert InsufficientBalance({ available: balance, required: tokenAmount });

		IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
		emit Recovered(tokenAddress, tokenAmount);
	}

	/* ========== MUTATIVE FUNCTIONS ========== */

	/**
	 * @notice Claim rewards for user.
	 * @dev In case there are no claimable rewards
	 * just update the user status and do nothing.
	 */
	function getReward() public nonReentrant {
		uint256 reward = earned(msg.sender);

		// this prevents user from re-claiming prev rewards
		firstUnclaimedReward[msg.sender] = rewards.length;
		if (reward == 0) return;

		currentBalance -= reward;

		IERC20(rewardsToken).safeTransfer(msg.sender, reward);
		emit RewardPaid(msg.sender, reward);
	}

	/* ========== VIEWS ========== */

	function getTotalRewards() public view returns (uint256) {
		return rewards.length;
	}

	/**
	 * @notice Calculates how much rewards a user earned
	 * @return amount of reward available to claim
	 */
	function earned(address owner) public view returns (uint256) {
		uint256 totalRewards = 0;
		for (uint256 i = firstUnclaimedReward[owner]; i < rewards.length; ++i) {
			totalRewards +=
				(rewards[i].amount *
					IVotingEscrow(veToken).balanceOfAt(owner, rewards[i].blockNumber)) /
				IVotingEscrow(veToken).totalSupplyAt(rewards[i].blockNumber);
		}
		return totalRewards;
	}

	/* ========== ERRORS ========== */

	error OnlyManager();
	error InsufficientBalance(uint256 available, uint256 required);
	error VaultIsEmpty();
	error TooEarlyToAddReward();
	error TooManyRewards();
	error NoRewardTokenBalance();

	/* ========== EVENTS ========== */

	event RewardAdded(uint256 reward);
	event RewardPaid(address indexed user, uint256 reward);
	event Recovered(address token, uint256 amount);
	event ChangeWhitelistERC20(address indexed tokenAddress, bool whitelistState);
}

