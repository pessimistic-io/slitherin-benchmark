// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

interface IVestaFarming {
	error Error_ZeroOwner();
	error Error_AlreadyInitialized();
	error Error_NotRewardDistributor();
	error Error_AmountTooLarge();

	event RewardAdded(uint256 reward);
	event Staked(address indexed user, uint256 amount);
	event Withdrawn(address indexed user, uint256 amount);
	event RewardPaid(address indexed user, uint256 reward);
	event EmergencyWithdraw(uint256 totalWithdrawn);
}

