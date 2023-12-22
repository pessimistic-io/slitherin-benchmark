// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.20;

/// @title Interface for Two Step Ownable contract
/// @author Timelord
interface IOwnable2Step {
    /// @dev Returns the address of the owner.
    /// @notice Returns zero when there is no owner.
    function owner() external view returns (address);

    /// @dev Returns the address of the pending owner.
    /// @notice Returns zero when there is no pending owner.
    function pendingOwner() external view returns (address);

    /// @dev Renounce ownership of the contract.
    /// @dev Can only be called by the owner.
    /// @dev The address of the owner will change to zero address.
    /// @notice This transaction cannot be reversed.
    /// @notice Owner must make sure any remaining rewards in the distributors are all withdrawn.
    function renounceOwnership() external;

    /// @dev Transfer the ownership to another address.
    /// @dev Can only be called by the owner.
    /// @dev Does not transfer the ownership immediately, instead set the pending owner first.
    /// @notice The pending owner must accept ownership to finalize the ownership transfer.
    /// @param newOwner The address of the new pending owner.
    function transferOwnership(address newOwner) external;

    /// @dev The new pending owner accepts the ownership transfer.
    /// @notice Can only be called by the pending owner.
    function acceptOwnership() external;
}

