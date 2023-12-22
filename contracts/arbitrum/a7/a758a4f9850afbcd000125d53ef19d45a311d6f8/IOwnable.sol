// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title IOwnable - Ownable Interface
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
interface IOwnable {
    // =========================
    // Events
    // =========================

    /// @notice Emits when ownership of the contract is transferred from `previousOwner`
    /// to `newOwner`.
    /// @param previousOwner The address of the previous owner.
    /// @param newOwner The address of the new owner.
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when the caller is not authorized to perform an operation.
    /// @param sender The address of the sender trying to access a restricted function.
    error Ownable_SenderIsNotOwner(address sender);

    /// @notice Thrown when the new owner is not a valid owner account.
    error Ownable_NewOwnerCannotBeAddressZero();

    // =========================
    // Main functions
    // =========================

    /// @notice Returns the address of the current owner.
    /// @return The address of the current owner.
    function owner() external view returns (address);

    /// @notice Leaves the contract without an owner. It will not be possible to call
    /// `onlyOwner` functions anymore.
    /// @dev Can only be called by the current owner.
    function renounceOwnership() external;

    /// @notice Transfers ownership of the contract to a new account (`newOwner`).
    /// @param newOwner The address of the new owner.
    /// @dev Can only be called by the current owner.
    function transferOwnership(address newOwner) external;
}

