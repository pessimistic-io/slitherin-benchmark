// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IOwnable} from "./IOwnable.sol";

/// @title Ownable
/// @dev Contract module which provides a basic access control mechanism, where
/// there is an account (an owner) that can be granted exclusive access to
/// specific functions.
///
/// By default, the owner account will be the one that deploys the contract. This
/// can later be changed with {transferOwnership}.
///
/// This module is used through inheritance. It will make available the modifier
/// `onlyOwner`, which can be applied to your functions to restrict their use to
/// the owner.
abstract contract Ownable is IOwnable {
    // =========================
    // Storage
    // =========================

    /// @dev Private variable to store the owner's address.
    address private _owner;

    // =========================
    // Main functions
    // =========================

    /// @notice Initializes the contract, setting the deployer as the initial owner.
    constructor() {
        _transferOwnership(msg.sender);
    }

    /// @dev Throws if called by any account other than the owner.
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /// @inheritdoc IOwnable
    function owner() external view returns (address) {
        return _owner;
    }

    /// @inheritdoc IOwnable
    function renounceOwnership() external onlyOwner {
        _transferOwnership(address(0));
    }

    /// @inheritdoc IOwnable
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert Ownable_NewOwnerCannotBeAddressZero();
        }

        _transferOwnership(newOwner);
    }

    // =========================
    // Internal functions
    // =========================

    /// @dev Internal function to verify if the caller is the owner of the contract.
    /// Errors:
    /// - Thrown `Ownable_SenderIsNotOwner` if the caller is not the owner.
    function _checkOwner() internal view {
        if (_owner != msg.sender) {
            revert Ownable_SenderIsNotOwner(msg.sender);
        }
    }

    /// @dev Transfers ownership of the contract to a new account (`newOwner`).
    /// @dev Emits an {OwnershipTransferred} event.
    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

