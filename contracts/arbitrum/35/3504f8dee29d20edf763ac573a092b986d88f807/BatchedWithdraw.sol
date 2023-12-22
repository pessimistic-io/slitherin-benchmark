// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "./ERC20.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { ERC4626 } from "./ERC4626.sol";

import "./console.sol";

struct WithdrawRecord {
	uint256 timestamp;
	uint256 shares;
	uint256 value; // this the current value (also max withdraw value)
}

abstract contract BatchedWithdraw is ERC4626 {
	using SafeERC20 for ERC20;

	event RequestWithdraw(address indexed caller, address indexed owner, uint256 shares);

	uint256 public lastHarvestTimestamp;
	uint256 public pendingWithdraw; // actual amount may be less

	mapping(address => WithdrawRecord) public withdrawLedger;

	constructor() {
		lastHarvestTimestamp = block.timestamp;
	}

	function requestRedeem(uint256 shares) public {
		return requestRedeem(shares, msg.sender);
	}

	function requestRedeem(uint256 shares, address owner) public {
		if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
		_transfer(owner, address(this), shares);
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];
		withdrawRecord.timestamp = block.timestamp;
		withdrawRecord.shares += shares;
		uint256 value = convertToAssets(shares);
		withdrawRecord.value = value;
		pendingWithdraw += value;
		emit RequestWithdraw(msg.sender, owner, shares);
	}

	function withdraw(
		uint256,
		address,
		address
	) public pure virtual override returns (uint256) {
		revert NotImplemented();
	}

	function redeem(
		uint256,
		address receiver,
		address
	) public virtual override returns (uint256 amountOut) {
		return redeem(receiver);
	}

	/// @dev safest UI method
	function redeem() public virtual returns (uint256 amountOut) {
		return redeem(msg.sender);
	}

	function redeem(address receiver) public virtual returns (uint256 amountOut) {
		uint256 shares;
		(amountOut, shares) = _redeem(msg.sender);
		ERC20(asset).transfer(receiver, amountOut);
		emit Withdraw(msg.sender, receiver, msg.sender, amountOut, shares);
	}

	/// @dev should only be called by manager on behalf of xVaults
	function _xRedeem(address xVault) internal virtual returns (uint256 amountOut) {
		uint256 shares;
		(amountOut, shares) = _redeem(xVault);
		_burn(address(this), shares);
		emit Withdraw(xVault, xVault, xVault, amountOut, shares);
	}

	function _redeem(address account) internal returns (uint256 amountOut, uint256 shares) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[account];

		if (withdrawRecord.value == 0) revert ZeroAmount();
		if (withdrawRecord.timestamp >= lastHarvestTimestamp) revert NotReady();

		shares = withdrawRecord.shares;
		// value of shares at time of redemption request
		uint256 redeemValue = withdrawRecord.value;
		uint256 currentValue = convertToAssets(shares);

		// actual amount out is the smaller of currentValue and redeemValue
		amountOut = currentValue < redeemValue ? currentValue : redeemValue;

		// update total pending withdraw
		pendingWithdraw -= redeemValue;

		// important pendingWithdraw should update prior to beforeWithdraw call
		beforeWithdraw(amountOut, shares);
		withdrawRecord.value = 0;
		_burn(address(this), shares);
	}

	function cancelRedeem() public virtual {
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];

		uint256 shares = withdrawRecord.shares;
		// value of shares at time of redemption request
		uint256 redeemValue = withdrawRecord.value;
		uint256 currentValue = convertToAssets(shares);

		// update accounting
		withdrawRecord.value = 0;
		pendingWithdraw -= redeemValue;

		// if vault lost money, shares stay the same
		if (currentValue < redeemValue) return _transfer(address(this), msg.sender, shares);

		// // if vault earned money, subtract earnings since withdrawal request
		uint256 sharesOut = (shares * redeemValue) / currentValue;
		uint256 sharesToBurn = shares - sharesOut;

		_transfer(address(this), msg.sender, sharesOut);
		_burn(address(this), sharesToBurn);
	}

	/// @notice UI method to view cancellation penalty
	function getPenalty() public view returns (uint256) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];
		uint256 shares = withdrawRecord.shares;

		uint256 redeemValue = withdrawRecord.value;
		uint256 currentValue = convertToAssets(shares);

		if (currentValue < redeemValue) return 0;
		return (1e18 * (currentValue - redeemValue)) / redeemValue;
	}

	/// UTILS
	function redeemIsReady(address user) external view returns (bool) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[user];
		return lastHarvestTimestamp > withdrawRecord.timestamp;
	}

	function getWithdrawStatus(address user) external view returns (WithdrawRecord memory) {
		return withdrawLedger[user];
	}

	error Expired();
	error NotImplemented();
	error NotReady();
	error ZeroAmount();
}

