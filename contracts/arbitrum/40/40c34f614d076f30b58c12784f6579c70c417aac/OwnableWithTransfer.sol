// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// loosely based on https://docs.synthetix.io/contracts/source/contracts/Owned

/// @title OwnableWithTransfer
/// @notice Contract module which provides a basic access control mechanism with
/// safe ownership transfer.
abstract contract OwnableWithTransfer {
	address public owner;
	address public pendingOwner;

	modifier onlyOwner() {
		if (msg.sender != owner) revert NotOwner();
		_;
	}

	constructor(address _owner) {
		if (_owner == address(0)) revert OwnerCannotBeZero();
		owner = _owner;
		emit OwnershipTransferred(address(0), _owner);
	}

	/// @dev Init transfer of ownership of the contract to a new account (`_pendingOwner`).
	/// @param _pendingOwner pending owner of contract
	/// Can only be called by the current owner.
	function transferOwnership(address _pendingOwner) external onlyOwner {
		pendingOwner = _pendingOwner;
		emit OwnershipTransferInitiated(owner, _pendingOwner);
	}

	/// @dev Accept transfer of ownership of the contract.
	/// Can only be called by the pendingOwner.
	function acceptOwnership() external {
		if (msg.sender != pendingOwner) revert OnlyPendingOwner();
		pendingOwner = address(0);
		owner = pendingOwner;
		emit OwnershipTransferred(owner, pendingOwner);
	}

	event OwnershipTransferInitiated(address owner, address pendingOwner);
	event OwnershipTransferred(address oldOwner, address newOwner);

	error OwnerCannotBeZero();
	error OnlyPendingOwner();
	error NotOwner();
}

