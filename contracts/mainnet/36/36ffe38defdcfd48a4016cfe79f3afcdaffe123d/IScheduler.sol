// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

error SchmintFailed();
error GasPriceExceedsLimit(uint256 transactionGasPrice, uint256 gasPriceLimit);
error AlreadyExecuted();
error AlreadyCancelled();
error SchmintingInactive();
error SchmintNotExist();
error TransferOfTransactionFeeFailed();
error NoFundsShouldBeTransferred();

struct SchmintInput {
    uint40 gasPriceLimit;
    address target;
    uint256 value;
    bytes data;
}

/// @title IScheduler
/// @author Chain Labs
/// @notice Interface of Scheduler contract
interface IScheduler {
    /// @notice initializes the scheduler and makes it ready for use
    /// @dev initializes scheduler, creates new gnosis safe and add schmints if any
    /// @param _owners address of owner
    /// @param _resolver address of simplr's resolver
    /// @param _schmints list of schmints to be added
    function initialize(
        address[] memory _owners,
        address _resolver,
        SchmintInput[] memory _schmints
    ) external payable;

    /// @notice execute schmint
    /// @dev schmint can only be executed by OPs contract
    /// @param schmintId ID of schmint which needs to be executed
    function executeSchmint(uint256 schmintId) external;
}

