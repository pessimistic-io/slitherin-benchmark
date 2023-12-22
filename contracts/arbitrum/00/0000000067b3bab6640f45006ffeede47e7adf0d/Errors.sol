// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Errors
/// @notice Library containing all custom errors the protocol may revert with.
library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                                      GENERICS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The address cannot be the zero address
    error AddressZero();
    /// @notice The signature is invalid
    error InvalidSignature();
    /// @notice Data does not match the expected format
    error InvalidData();
    /// @notice Nonce has already been used
    error NonceAlreadyUsed();
    /// @notice Deadline has expired
    error DeadlineExpired();
    /// @notice Only Supa can call this function
    error OnlySupa();
    /// @notice Only the owner or operator can call this function
    error NotOwnerOrOperator();
    /// @notice Only the owner can call this function
    error OnlyOwner();
    /// @notice Only this address can call this function
    error OnlyThisAddress();
    /// @notice Transfer failed
    error TransferFailed();

    /*//////////////////////////////////////////////////////////////////////////
                                  ERC20
    //////////////////////////////////////////////////////////////////////////*/


    /*//////////////////////////////////////////////////////////////////////////
                                  ERC721
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The receiving address is not a contract
    error ReceiverNotContract();
    /// @notice The receiver does not implement the required interface
    error ReceiverNoImplementation();
    /// @notice The receiver did not return the correct value - transaction failed
    error WrongDataReturned();

    /*//////////////////////////////////////////////////////////////////////////
                                  ORACLES
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Borrow factor must be greater than zero
    error InvalidBorrowFactor();
/// @notice Chainlink price oracle must return a valid price (>0)
    error InvalidPrice();

    /*//////////////////////////////////////////////////////////////////////////
                                  SUPA
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Sender is not approved to spend wallet erc20
    error NotApprovedOrOwner();
    /// @notice Sender is not the owner of the wallet;
    /// @param sender The address of the sender
    /// @param owner The address of the owner
    error NotOwner(address sender, address owner);
    /// @notice Transfer amount exceeds allowance
    error InsufficientAllowance();
    /// @notice Cannot approve self as spender
    error SelfApproval();
    /// @notice Asset is not an NFT
    error NotNFT();
    /// @notice NFT must be owned the the user or user's wallet
    error NotNFTOwner();
    /// @notice Operation leaves wallet insolvent
    error Insolvent();
    /// @notice Thrown if a wallet accumulates too many assets
    error SolvencyCheckTooExpensive();
    /// @notice Cannot withdraw debt
    error CannotWithdrawDebt();
    /// @notice Wallet is not liquidatable
    error NotLiquidatable();
    /// @notice There are insufficient reserves in the protocol for the debt
    error InsufficientReserves();
    /// @notice This operation would add too many tokens to the credit account
    error TokenStorageExceeded();
    /// @notice The address is not a registered ERC20
    error NotERC20();
    /// @notice `newOwner` is not the proposed new owner
    /// @param proposedOwner The address of the proposed new owner
    /// @param newOwner The address of the attempted new owner
    error InvalidNewOwner(address proposedOwner, address newOwner);
    /// @notice Only wallet can call this function
    error OnlyWallet();
    /// @notice Recipient is not a valid wallet
    error WalletNonExistent();
    /// @notice Asset is not registered
    /// @param token The unregistered asset
    error NotRegistered(address token);
    /// @notice Thrown when the function is unimplemented
    error NotImplemented();

    /*//////////////////////////////////////////////////////////////////////////
                                  VERSION MANAGER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The implementation must be a contract
    error InvalidImplementation();
    /// @notice The version is deprecated
    error DeprecatedVersion();
    /// @notice The bug level is too high
    error BugLevelTooHigh();
    /// @notice Recommended Version does not exist
    error NoRecommendedVersion();
    /// @notice version is not registered
    error VersionNotRegistered();
    /// @notice Specified status is out of range
    error InvalidStatus();
    /// @notice Specified bug level is out of range
    error InvalidBugLevel();
    /// @notice version name cannot be the empty string
    error InvalidVersionName();
    /// @notice version is deprecated or has a bug
    error InvalidVersion();
    /// @notice version is already registered
    error VersionAlreadyRegistered();


    /*//////////////////////////////////////////////////////////////////////////
                                  TRANSFER AND CALL 2
    //////////////////////////////////////////////////////////////////////////*/

    error TransfersUnsorted();

    error EthDoesntMatchWethTransfer();

    error UnauthorizedOperator(address operator, address from);

    error ExpiredPermit();
}
