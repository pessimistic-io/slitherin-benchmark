// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import { IERC20TokenReceiver } from "./IERC20TokenReceiver.sol";

import { PausableAccessControl } from "./PausableAccessControl.sol";
import { TokenUtils } from "./TokenUtils.sol";
import { SafeCast } from "./SafeCast.sol";
import "./Errors.sol";

contract RewardRouter is IERC20TokenReceiver, PausableAccessControl, ReentrancyGuard {
	/// @notice The number of basis points there are to represent exactly 100%.
	uint256 public constant BPS = 10_000;

	/// @notice The address of the reward token routed by the contract.
	address public immutable rewardToken;

	/// @notice Gets the address of the contract that receives the harvested rewards.
	address public rewardReceiver;

	/// @notice The share of each profitable harvest that will go to the protocol fee receiver address.
	uint256 public protocolFee;

	/// @notice The address of the contract which will receive fees.
	address public protocolFeeReceiver;

	constructor(
		address _rewardToken,
		address _rewardReceiver,
		address _protocolFeeReceiver,
		uint256 _protocolFee
	) {
		rewardToken = _rewardToken;
		rewardReceiver = _rewardReceiver;
		protocolFeeReceiver = _protocolFeeReceiver;
		protocolFee = _protocolFee;
	}

	/// @notice Sets the rewardReceiver.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	/// @notice Reverts with an {ZeroAddress} error if the reward receiver is the 0 address.
	///
	/// @notice Emits a {RewardReceiverUpdated} event.
	///
	/// @param _rewardReceiver the address of the reward receiver that receives the rewards.
	function setRewardReceiver(address _rewardReceiver) external {
		_onlyAdmin();
		if (_rewardReceiver == address(0)) {
			revert ZeroAddress();
		}

		rewardReceiver = _rewardReceiver;

		emit RewardReceiverUpdated(rewardReceiver);
	}

	/// @notice Sets the address of the protocol fee receiver.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	/// @notice Reverts with an {ZeroAddress} error if the new protocol fee receiver is the 0 address.
	///
	/// @notice Emits a {ProtocolFeeReceiverUpdated} event.
	///
	/// @param _protocolFeeReceiver The address of the new receiver.
	function setProtocolFeeReceiver(address _protocolFeeReceiver) external {
		_onlyAdmin();
		if (_protocolFeeReceiver == address(0)) {
			revert ZeroAddress();
		}
		protocolFeeReceiver = _protocolFeeReceiver;

		emit ProtocolFeeReceiverUpdated(_protocolFeeReceiver);
	}

	/// @notice Sets the protocol fee amount.
	///
	/// @notice Reverts with an {OnlyAdminAllowed} error if the caller is missing the admin role.
	/// @notice Reverts with an {MaxProtocolFeeBreached} error if the new protocol fee is greater than 100%.
	///
	/// @notice Emits a {ProtocolFeeUpdated} event.
	///
	/// @param _protocolFee The new protocol fee.
	function setProtocolFee(uint256 _protocolFee) external {
		_onlyAdmin();
		if (_protocolFee > BPS) {
			revert MaxProtocolFeeBreached();
		}
		protocolFee = _protocolFee;

		emit ProtocolFeeUpdated(_protocolFee);
	}

	/// @inheritdoc IERC20TokenReceiver
	function onERC20Received(address _token, uint256 _amount) external nonReentrant {
		_distribute();
	}

	/// @notice Distributes rewards deposited into the zoo by the vault.
	/// @notice Fees are deducted from the rewards and sent to the fee receiver.
	/// @notice Remaining rewards reduce users' debts and are sent to the keeper.
	function _distribute() internal {
		uint256 _harvestedAmount = TokenUtils.safeBalanceOf(rewardToken, address(this));

		if (_harvestedAmount > 0) {
			uint256 _feeAmount = (_harvestedAmount * protocolFee) / BPS;

			// Transfers fees to protocol fee receiver
			if (_feeAmount > 0) {
				TokenUtils.safeTransfer(rewardToken, protocolFeeReceiver, _feeAmount);
			}

			// Transfers remaining to reward receiver
			uint256 _distributeAmount = _harvestedAmount - _feeAmount;
			if (_distributeAmount > 0) {
				address _rewardReceiver = rewardReceiver;
				TokenUtils.safeTransfer(rewardToken, _rewardReceiver, _distributeAmount);
				IERC20TokenReceiver(_rewardReceiver).onERC20Received(rewardToken, _distributeAmount);
			}
		}
		emit HarvestRewardDistributed(_harvestedAmount);
	}

	/// @notice Emitted when the reward receiver is updated.
	///
	/// @param rewardReceiver The address of the reward receiver.
	event RewardReceiverUpdated(address rewardReceiver);

	/// @notice Emitted when rewards are distributed.
	///
	/// @param amount The amount of native tokens distributed.
	event ProtocolFeeUpdated(uint256 amount);

	/// @notice Emitted when the reward address is updated.
	///
	/// @param reward The address receiving rewards.
	event ProtocolFeeReceiverUpdated(address reward);

	/// @notice Emitted when rewards are distributed.
	///
	/// @param amount The amount of native tokens distributed.
	event HarvestRewardDistributed(uint256 amount);

	/// @notice Indicates that the max allowed protocol fee has been breached.
	error MaxProtocolFeeBreached();
}

