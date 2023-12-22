// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import "./IProtocolRevenue.sol";

import "./BaseVesta.sol";
import "./IERC20Callback.sol";
import { TokenTransferrer } from "./TokenTransferrer.sol";

/**
@title ProtocolRevenue
@notice All the protocol's revenues are held here
*/
contract ProtocolRevenue is
	IProtocolRevenue,
	IERC20Callback,
	TokenTransferrer,
	BaseVesta
{
	bytes1 public constant DEPOSIT = 0x01;

	bool public isPaused;
	address public treasury;

	mapping(address => uint256) internal rewards;
	mapping(address => uint256) internal rewardsSentToTreasury;

	function setUp(address _treasury)
		external
		initializer
		onlyValidAddress(_treasury)
	{
		__BASE_VESTA_INIT();
		treasury = _treasury;
	}

	function claimRewards(address _token) external override nonReentrant {
		//TODO -> Once veModel is defined.
		emit RewardsChanged(_token, rewards[_token]);
	}

	function setTreasury(address _newTreasury)
		external
		override
		onlyOwner
		onlyValidAddress(_newTreasury)
	{
		treasury = _newTreasury;
	}

	function withdraw(address _token, uint256 _amount) external override onlyOwner {
		uint256 sanitizedValue = _sanitizeValue(_token, _amount);
		if (sanitizedValue == 0) return;

		uint256 newTotal = rewards[_token] -= _amount;

		_performTokenTransfer(_token, msg.sender, sanitizedValue, false);
		emit RewardsChanged(_token, newTotal);
	}

	function setPause(bool _pause) external override onlyOwner {
		isPaused = _pause;
	}

	function receiveERC20(address _token, uint256 _amount)
		external
		override
		hasPermission(DEPOSIT)
	{
		if (isPaused) {
			_performTokenTransfer(_token, treasury, _amount, false);
			rewardsSentToTreasury[_token] += _amount;
		} else {
			uint256 newTotal = rewards[_token] += _amount;
			emit RewardsChanged(_token, newTotal);
		}
	}

	receive() external payable {
		if (isPaused) {
			_performTokenTransfer(RESERVED_ETH_ADDRESS, treasury, msg.value, false);
			rewardsSentToTreasury[RESERVED_ETH_ADDRESS] += msg.value;
		} else {
			uint256 newTotal = rewards[RESERVED_ETH_ADDRESS] += msg.value;
			emit RewardsChanged(RESERVED_ETH_ADDRESS, newTotal);
		}
	}

	function getRewardBalance(address _token)
		external
		view
		override
		returns (uint256)
	{
		return rewards[_token];
	}

	function getRewardBalanceSentToTreasury(address _token)
		external
		view
		override
		returns (uint256)
	{
		return rewardsSentToTreasury[_token];
	}
}

