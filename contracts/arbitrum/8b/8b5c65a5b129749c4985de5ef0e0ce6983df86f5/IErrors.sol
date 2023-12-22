// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IErrors {
    // Generic Errors
    error InvalidInput();
    error InsufficientBalance();

    // Vault Errors
    error VaultNotApproved();
    error FundsNotDeployed();
    error FundsAlreadyDeployed();
    error InvalidLengths();
    error InvalidUnqueueAmount();
    error InvalidWeightId();
    error InvalidQueueSize();
    error InvalidQueueId();
    error InvalidArrayLength();
    error InvalidDepositAmount();
    error NegativeEmissions();
    error ZeroShares();
    error QueuedAmountInsufficient();
    error NoQueuedWithdrawals();
    error QueuedWithdrawalPending();
    error UnableToUnqueue();
    error PositionClosePending();

    // Hook Errors
    error Unauthorized();
    error VaultSet();
    error AssetIdNotSet();
    error InvalidPathCount();
    error OutdatedPathInfo();
    error InvalidToken();

    // Queue Contract Errors
    error InvalidAsset();

    // Getter Errors
    error InvalidVaultAddress();
    error InvalidVaultAsset();
    error InvalidVaultEmissions();
    error MarketNotExist();
    error InvalidVaultController();
    error InvalidVaultCounterParty();
    error InvalidTreasury();
    error InvalidVaultEpoch();

    // Position Sizer
    error InvalidWeightStrategy();
    error ProportionUnassigned();
    error LengthMismatch();
    error NoValidThreshold();

    // DEX Errors
    error InvalidPath();
    error InvalidCaller();
    error InvalidMinOut(uint256 amountOut);
}

