// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IOFT.sol";

contract ZooDAOProxy is Ownable {
	address private _commissionReceiver;
	uint256 private _commissionAmountInNative;
	address public token;
	IOFT private tokenInstance;

	event CommissionAmountUpdated(uint256 oldCommissionAmount, uint256 newCommissionAmount);

	event CommissionReceiverUpdated(address oldCommissionReceiver, address newCommissionReceiver);

	event BridgeWithCommission(uint256 amount, uint256 amountWithoutCommission, uint256 commission);

	constructor(
		address token_,
		address commisionReceiver_,
		uint256 commissionAmountInNative_
	) {
		_commissionReceiver = commisionReceiver_;
		_commissionAmountInNative = commissionAmountInNative_;

		token = token_;
		tokenInstance = IOFT(token_);
	}

	function estimateSendFee(
		uint16 _dstChainId,
		bytes calldata _toAddress,
		uint256 _amount,
		bool _useZro,
		bytes calldata _adapterParams
	) public view returns (uint256 nativeFee, uint256 zroFee) {
		(nativeFee, zroFee) = tokenInstance.estimateSendFee(_dstChainId, _toAddress, _amount, _useZro, _adapterParams);
		nativeFee += _commissionAmountInNative;
	}

	function sendFrom(
		address _from,
		uint16 _dstChainId,
		bytes calldata _toAddress,
		uint256 _amount,
		address payable _refundAddress,
		address _zroPaymentAddress,
		bytes calldata _adapterParams
	) public payable {
		uint256 newValue = deductCommissionInNative();
		tokenInstance.sendFrom{value: newValue}(
			_from,
			_dstChainId,
			_toAddress,
			_amount,
			_refundAddress,
			_zroPaymentAddress,
			_adapterParams
		);
	}

	function deductCommissionInNative() internal returns (uint256 newFeeAmount) {
		(bool success, ) = _commissionReceiver.call{value: _commissionAmountInNative}('');
		require(success, 'Fee is too low. Get fee amount from estimateSendFee()');

		emit BridgeWithCommission(msg.value, msg.value - _commissionAmountInNative, _commissionAmountInNative);

		return msg.value - _commissionAmountInNative;
	}

	function updateCommissionAmount(uint256 commissionAmountInNative_) external onlyOwner {
		uint256 oldCommissionAmountInNative = _commissionAmountInNative;
		_commissionAmountInNative = commissionAmountInNative_;

		emit CommissionAmountUpdated(oldCommissionAmountInNative, _commissionAmountInNative);
	}

	function updateCommissionReceiver(address commisionReceiver_) external onlyOwner {
		address oldCommissionReceiver = _commissionReceiver;
		_commissionReceiver = commisionReceiver_;

		emit CommissionReceiverUpdated(oldCommissionReceiver, _commissionReceiver);
	}
}

