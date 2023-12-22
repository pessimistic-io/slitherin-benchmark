// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "./SafeERC20.sol";

/// @title Disbursement contract - allows to distribute tokens over time with a cliff
/// @author Stefan George - <stefan@gnosis.pm> modified by New Order Team
contract DisbursementCliff {
	using SafeERC20 for IERC20;
	/*
	 *  Storage
	 */
	address public receiver;
	address public wallet;
	uint256 public disbursementPeriod;
	uint256 public startDate;
	uint256 public cliffDate;
	uint256 public withdrawnTokens;
	/// tokens are locked until wallet unlocks them
	bool public locked = true;
	IERC20 public token;

	/*
	 *  Modifiers
	 */
	modifier isReceiver() {
		if (msg.sender != receiver) revert("Only receiver is allowed to proceed");
		_;
	}

	modifier isWallet() {
		if (msg.sender != wallet) revert("Only wallet is allowed to proceed");
		_;
	}

	/*
	 *  Public functions
	 */
	/// @dev Constructor function sets the wallet address, which is allowed to withdraw all tokens anytime
	/// @param _receiver Receiver of vested tokens
	/// @param _wallet Gnosis multisig wallet address
	/// @param _disbursementPeriod Vesting period in seconds
	/// @param _startDate Start date of disbursement period
	/// @param _cliffDate Time of cliff, before which tokens cannot be withdrawn
	/// @param _token ERC20 token used for the vesting
	constructor(
		address _receiver,
		address _wallet,
		uint256 _disbursementPeriod,
		uint256 _startDate,
		uint256 _cliffDate,
		IERC20 _token
	) {
		if (
			_receiver == address(0) ||
			_wallet == address(0) ||
			_disbursementPeriod == 0 ||
			address(_token) == address(0)
		) revert("Arguments are null");
		receiver = _receiver;
		wallet = _wallet;
		disbursementPeriod = _disbursementPeriod;
		startDate = _startDate;
		cliffDate = _cliffDate;
		token = _token;
		if (startDate == 0) {
			startDate = block.timestamp;
		}
		if (cliffDate < startDate) {
			cliffDate = startDate;
		}
	}

	/// @dev multisig wallet unlocks tokens
	function unlock() external isWallet {
		locked = false;
	}

	/// @dev Transfers tokens to a given address
	/// @param _to Address of token receiver
	/// @param _value Number of tokens to transfer
	function withdraw(address _to, uint256 _value) external isReceiver {
		if (locked) revert("Tokens are locked");
		uint256 maxTokens = calcMaxWithdraw();
		if (_value > maxTokens) {
			revert("Withdraw amount exceeds allowed tokens");
		}
		withdrawnTokens += _value;
		token.safeTransfer(_to, _value);
	}

	/// @dev Transfers all tokens to multisig wallet
	function walletWithdraw() external isWallet {
		uint256 balance = token.balanceOf(address(this));
		withdrawnTokens += balance;
		token.safeTransfer(wallet, balance);
	}

	/// @dev Calculates the maximum amount of vested tokens
	/// @return Number of vested tokens to withdraw
	function calcMaxWithdraw() public view returns (uint256) {
		if (startDate > block.timestamp || cliffDate > block.timestamp) return 0;

		uint256 maxTokens = ((token.balanceOf(address(this)) + withdrawnTokens) *
			(block.timestamp - startDate)) / disbursementPeriod;

		if (withdrawnTokens >= maxTokens) return 0;

		return maxTokens - withdrawnTokens;
	}
}

