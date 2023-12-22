// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// ===============
//    IMPORTS
// ===============
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import "./VM.sol";
import "./vault_AccessControl.sol";
import "./OperationsQueue.sol";

import "./vm_Constants.sol";
import "./ITokenStash.sol";
import "./VaultUtilities.sol";
import "./VaultExecution.sol";

/**
 * The part of the vault contract containing various
 * state (storage) variables and immutables.
 *
 * This is the root contract being inherited
 */

contract Vault is VaultExecution {
    // LIBS
    using SafeERC20 for IERC20;

    // =====================
    //      CONSTRUCTOR
    // =====================
    /**
     * @notice
     * The constructor,
     * accepts all of the different configs for this strategy contract
     * @param steps - A linked list of YCStep. a YCStep specifies the encoded FunctionCall of a step,
     * the indexes of it's children within the array, and an optional array of "conditions".
     * In which case it means the step is a conditional block.
     * @param seedSteps - A linked list of YCStep like the above, this time,
     * for the seed strategy (i.e, the strategy that runs on deposit)
     * @param uprootSteps - Another linked list of YCStep,
     * but for the "Uprooting" strategy (the reverse version of the strategy)
     * @param approvalPairs - A 2D array of addresses -
     * at index 0 there is an ERC20-compatible token contract address, and at index 1 there is a
     * contract address to approve. This is in order to iterate over and pre-approve all addresses required.
     * @param depositToken - The token of this vault that users deposit into here, as an address
     *
     * @param ispublic - Whether the vault is publicly accessible or not
     */
    constructor(
        bytes[] memory seedSteps,
        bytes[] memory steps,
        bytes[] memory uprootSteps,
        address[2][] memory approvalPairs,
        IERC20 depositToken,
        bool ispublic,
        address creator
    )
        VaultState(
            seedSteps,
            steps,
            uprootSteps,
            approvalPairs,
            depositToken,
            ispublic,
            creator
        )
    {}

    // ==============================
    //     PUBLIC VAULT METHODS
    // ==============================

    /**
     * @notice
     * Request A Deposit Into The Vault
     * @param amount - The amount of the deposit token to deposit
     */
    function deposit(
        uint256 amount
    ) external payable onlyWhitelistedOrPublicVault {
        /**
         * We assert that the user must have given us appropriate allowance of the deposit token,
         * so that we can transfer the amount to us
         */
        if (DEPOSIT_TOKEN.allowance(msg.sender, address(this)) < amount)
            revert InsufficientAllowance();

        /**
         * @dev We assert that the msg.value of this call is atleast of the deposit approximation * the delta
         */
        if (msg.value < approxDepositGas * GAS_FEE_APPROXIMATION_DELTA)
            revert InsufficientGasPrepay();

        /**
         * @notice
         * We get the user's tokens into our balance, and then @dev stash it on the Yieldchain Diamond's TokenStasher facet.
         * This is in order for us to get the tokens right away, without messing with the balances of other operations
         */

        // Transfer to us
        DEPOSIT_TOKEN.safeTransferFrom(msg.sender, address(this), amount);

        // Stash in TokenStasher
        ITokenStash(YC_DIAMOND).stashTokens(address(DEPOSIT_TOKEN), amount);

        // Increment total shares supply & user's balance
        totalShares += amount;
        balances[msg.sender] += amount;

        /**
         * Create an operation item, and request it (adding to the state array & emitting an event w a request to handle)
         */

        // Create the args array which just includes the encoded amount
        bytes[] memory depositArgs = new bytes[](1);
        depositArgs[0] = abi.encode(amount);

        // Create the queue item
        OperationItem memory depositRequest = OperationItem(
            ExecutionTypes.SEED,
            msg.sender,
            msg.value,
            depositArgs,
            new bytes[](0),
            false
        );

        // Request the operation
        requestOperation(depositRequest);
    }

    /**
     * @notice
     * Request to withdraw out of the vault
     * @param amount - the amount of shares to withdraw
     */
    function withdraw(
        uint256 amount
    ) external payable onlyWhitelistedOrPublicVault {
        /**
         * We assert the user's shares are sufficient
         * Note this is re-checked when handling the actual withdrawal
         */
        if (amount > balances[msg.sender]) revert InsufficientShares();

        /**
         * @dev We assert that the msg.value of this call is atleast of the withdraw approximation * the delta
         */
        if (msg.value < approxWithdrawalGas * GAS_FEE_APPROXIMATION_DELTA)
            revert InsufficientGasPrepay();

        /**
         * We deduct the total shares & balance from the user
         */
        balances[msg.sender] -= amount;
        totalShares -= amount;

        /**
         * We create an Operation request item for our withdrawal and add it to the state, whilst requesting an offchain hydration & reentrance
         */
        bytes[] memory withdrawArgs = new bytes[](1);
        withdrawArgs[0] = abi.encode(amount);

        // Create the queue item
        OperationItem memory withdrawRequest = OperationItem(
            ExecutionTypes.UPROOT,
            msg.sender,
            msg.value,
            withdrawArgs,
            new bytes[](0),
            false
        );

        // Request the operation
        requestOperation(withdrawRequest);
    }

    /**
     * @notice
     * runStrategy()
     * Requests a strategy execution operation,
     * only called by the diamond (i.e from an executor on the diamond)
     */
    function runStrategy() external onlyDiamond {
        /**
         * We create a QueueItem for our run and enqueue it, which should either begin executing it,
         * or begin waiting for it's turn
         */
        // Create the queue item
        OperationItem memory runRequest = OperationItem(
            // Request to execute the strategy tree
            ExecutionTypes.TREE,
            // Initiator is YC diamond
            YC_DIAMOND,
            // Gas not required here (using gas balance of entire vault)
            0,
            // No custom args, and ofc no calldata atm (will be set by the offchain handler if any)
            new bytes[](0),
            new bytes[](0),
            false
        );

        // Request the run
        requestOperation(runRequest);
    }
}

