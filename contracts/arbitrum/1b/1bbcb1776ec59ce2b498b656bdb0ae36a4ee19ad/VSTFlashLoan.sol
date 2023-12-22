// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./OwnableUpgradeable.sol";
import { TokenTransferrer } from "./TokenTransferrer.sol";
import "./VestaMath.sol";
import "./IFlashLoanExecutor.sol";
import "./IVSTFlashLoan.sol";
import "./IBorrowerOperations.sol";

contract VSTFlashLoan is OwnableUpgradeable, TokenTransferrer, IVSTFlashLoan {
	IBorrowerOperations public borrowerOperations;
	address public VST;
	uint256 public feePercentage; // 4 decimals. 10000 = 100%, 100 = 1%.
	uint256 public constant feePercentageDenominator = 10000;
	address public feeReciever;
	mapping(address => bool) private hasPermission;
	bool public isOpen;

	function setUp(
		address _VST,
		address _borrowerOperations,
		address _feeReciever,
		uint256 _feePercentage
	) external initializer {
		__Ownable_init();
		VST = _VST;
		borrowerOperations = IBorrowerOperations(_borrowerOperations);
		feePercentage = _feePercentage;
		feeReciever = _feeReciever;
	}

	modifier validatePermission(address _user) {
		if (!isOpen && !hasPermission[_user]) revert Unauthorized();
		_;
	}

	function setFeePercentage(uint256 _feePercentage) external onlyOwner {
		feePercentage = _feePercentage;
	}

	function setFeeReciever(address _feeReciever) external onlyOwner {
		feeReciever = _feeReciever;
	}

	function setPermission(address _user, bool _hasAccess) external onlyOwner {
		hasPermission[_user] = _hasAccess;
	}

	function setOpen(bool _isOpen) external onlyOwner {
		isOpen = _isOpen;
	}

	function executeFlashLoan(
		uint256 _amount,
		address _executor,
		bytes calldata _extraParams
	) external override validatePermission(msg.sender) {
		uint256 feeAmount = VestaMath.mulDiv(
			_amount,
			feePercentage,
			feePercentageDenominator
		);

		borrowerOperations.mint(_executor, _amount);

		IFlashLoanExecutor(_executor).executeOperation(
			_amount,
			feeAmount,
			msg.sender,
			_extraParams
		);

		borrowerOperations.burn(_executor, _amount);

		_performTokenTransferFrom(
			address(VST),
			_executor,
			feeReciever,
			feeAmount,
			false
		);

		emit FlashLoanSuccess(msg.sender, _executor, _amount);
	}

	function getPermission(address _user) external view returns (bool) {
		return hasPermission[_user];
	}
}


