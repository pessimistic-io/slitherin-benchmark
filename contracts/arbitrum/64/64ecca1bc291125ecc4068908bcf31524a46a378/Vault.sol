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

/**
 * The part of the vault contract containing various
 * state (storage) variables and immutables.
 *
 * This is the root contract being inherited
 */

contract Vault is
    YCVM,
    OperationsQueue,
    AccessControl,
    VaultUtilities,
    VaultConstants
{
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
    ) AccessControl(creator, msg.sender) {
        /**
         * @dev We set the immutable set of steps, seed steps, and uproot steps
         */
        STEPS = steps;
        SEED_STEPS = seedSteps;
        UPROOTING_STEPS = uprootSteps;

        /**
         * @dev We set the depositToken immutable variable
         */
        DEPOSIT_TOKEN = depositToken;

        /**
         * @dev
         * We set the vault's initial privacy
         */
        isPublic = ispublic;

        /**
         * @dev We iterate over each approval pair and approve them as needed.
         */
        for (uint256 i = 0; i < approvalPairs.length; i++) {
            address addressToApprove = approvalPairs[i][1];
            addressToApprove = addressToApprove == address(0)
                ? msg.sender // The diamond
                : addressToApprove;

            IERC20(approvalPairs[i][0]).approve(
                addressToApprove,
                type(uint256).max
            );
        }

        /**
         * @dev We also add mods and admin permission to the creator
         */
        admins[creator] = true;
        mods[creator] = true;
        whitelistedUsers[creator] = true;
    }

    // =====================
    //      IMMUTABLES
    // =====================

    /**
     * @dev The deposit token of the vault
     */
    IERC20 public immutable DEPOSIT_TOKEN;

    /**
     * @notice
     * @dev
     * A linked list containing the tree of (encoded) steps to execute on the main triggers
     */
    bytes[] internal STEPS;

    /**
     * @dev Just as the above -
     * A linked list of encoded steps, but for the seed strategy (runs on deposit, i.e initial allocations)
     */
    bytes[] internal SEED_STEPS;

    /**
     * @dev Another linked list of steps,
     * but for the "uprooting" strategy (A "reverse" version of the strategy, executed on withdrawals)
     */
    bytes[] internal UPROOTING_STEPS;

    /**
     * @notice @dev
     * Used in offchain simulations when hydrating calldata
     */
    bool isMainnet = true;

    // ==============================
    //           STORAGE
    // ==============================
    /**
     * @notice
     * The total amount of shares of this vault, directly correlated with deposit tokens
     * 1 token deposited += totalShares(1)
     * 1 token withdrawan -= totalShares(1)
     */
    uint256 public totalShares;

    /**
     * @notice
     * Mapping user addresses to their corresponding balances of vault shares
     */
    mapping(address => uint256) public balances;

    /**
     * @notice
     * Active share percentage,
     * used to track withdrawals incase of an offchain execution required mid way
     */
    uint256 activeShare;

    /**
     * @notice
     * @dev
     * We keep track of the approximate gas required to execute withdraw and deposit operations.
     * This is in order to charge users for the gas they are going to cost the executor
     * after their offchain hydration.
     *
     * We also keep track of the gas for the strategy run operation, mainly for analytical purposes, tho.
     */
    uint256 public approxWithdrawalGas = 0.01 ether;

    uint256 public approxDepositGas = 0.01 ether;

    uint256 public approxStrategyGas = 0.01 ether;

    /**
     * @dev This state variable indiciates whether we are locked or not,
     * this is used by the offchain in order to not process additional requests until
     * we are unlocked
     */
    bool locked;

    // =====================
    //        GETTERS
    // =====================
    function getVirtualStepsTree(
        ExecutionTypes executionType
    ) external view returns (bytes[] memory) {
        if (executionType == ExecutionTypes.SEED) return SEED_STEPS;
        if (executionType == ExecutionTypes.TREE) return STEPS;
        if (executionType == ExecutionTypes.UPROOT) return UPROOTING_STEPS;
        revert();
    }

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
            new bytes[](0)
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
            new bytes[](0)
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
            new bytes[](0)
        );

        // Request the run
        requestOperation(runRequest);
    }

    // =========================================
    //       DIAMOND-PERMISSIONED METHODS
    // =========================================

    /**
     * hydrateAndExecuteRun
     * Hydrates an OperationItem from storage with provided calldatas and executes it
     * @param operationIndex - The index of the operation from within storage
     * @param commandCalldatas - Array of arbitrary YC commands, should be the fullfilling calldatas for the
     * run if required
     */
    function hydrateAndExecuteRun(
        uint256 operationIndex,
        bytes[] memory commandCalldatas
    ) external onlyDiamond returns (OperationItem memory operation) {
        /**
         * We retreive the current operation to handle.
         * Note that we do not dequeue it, as we want it to remain visible in storage
         * until the operation fully completes (incase there is an offchain break inbetween execution steps).
         * Dequeuing it & resaving to storage would be highly unneccsery gas-wise, and hence we leave it in the queue,
         * and leave it upto the handling function to dequeue it
         */

        operation = operationRequests[operationIndex];

        // We lock the contract state
        locked = true;

        /**
         * We hydrate it with the command calldatas
         */
        operation.commandCalldatas = commandCalldatas;

        /**
         * Switch statement for the operation to run
         */
        if (operation.action == ExecutionTypes.SEED) executeDeposit(operation);
        else if (operation.action == ExecutionTypes.UPROOT)
            executeWithdraw(operation);
        else if (operation.action == ExecutionTypes.TREE)
            executeStrategy(operation);
        else revert();

        // We unlock the contract state once the operation has completed
        locked = false;
    }

    /**
     * @dev
     * Claim gas paid by an operation request
     * @param operationIndex - The index of the operation in storage
     * @param receiver - The address of the executor that should receive this transfer
     * @param claimAmount - The amount of gas to claim
     */
    function claimOperationGas(
        uint256 operationIndex,
        address payable receiver,
        uint256 claimAmount
    ) external onlyDiamond {
        // Get the amount of gas that was included in this request
        OperationItem memory opRequest = operationRequests[operationIndex];
        uint256 availableAmt = opRequest.gas;

        // Make sure claim amount is sufficient to the available amount
        require(
            availableAmt >= claimAmount,
            "Insufficient Request Gas To Claim"
        );

        // Set the gas in the storage item to 0, since we now claim the gas there shouldnt be a need for that
        operationRequests[operationIndex].gas = 0;

        // Transfer requested gas to diamond
        // Note that the Diamond is responsible for refunding unused gas at the end.
        payable(receiver).transfer(claimAmount);
    }

    /**
     * storeGasApproximation()
     * Stores a gas approximation for some action
     * @param operationType - ExecutionType enum so that we know where to store to
     * @param approximation - The approximation of gas
     */
    function storeGasApproximation(
        ExecutionTypes operationType,
        uint256 approximation
    ) external onlyDiamond {
        // Switch case based on the type
        if (operationType == ExecutionTypes.SEED)
            approxDepositGas = approximation;
        else if (operationType == ExecutionTypes.UPROOT)
            approxWithdrawalGas = approximation;
        else if (operationType == ExecutionTypes.TREE)
            approxStrategyGas = approximation;
    }

    // ============================
    //       INTERNAL METHODS
    // ============================
    /**
     * @notice
     * executeDeposit()
     * The actual deposit execution handler,
     * @dev Should be called once hydrated with the operation offchain computed data
     * @param depositItem - OperationItem from the operations queue, representing the deposit request
     */
    function executeDeposit(OperationItem memory depositItem) internal {
        /**
         * @dev
         * At this point, we have transferred the user's funds to our stash in the Diamond,
         * and had the offchain handler hydrate our item's calldatas (if any are required).
         */

        /**
         * Decode the first byte argument as an amount
         */
        uint256 amount = abi.decode(depositItem.arguments[0], (uint256));

        assembly {
            // We MSTORE at the deposit amount memory location the deposit amount (may be accessed by commands to determine amount arguments)
            mstore(DEPOSIT_AMT_MEM_LOCATION, amount)
            // Update the free mem pointer (we know it in advanced no need to mload on existing stored ptr)
            mstore(0x40, add(DEPOSIT_AMT_MEM_LOCATION, 0x20))
        }

        /**
         * We unstash the user's tokens from the Yieldchain Diamond, so that it is (obv) used within the operation
         */
        ITokenStash(YC_DIAMOND).unstashTokens(address(DEPOSIT_TOKEN), amount);

        /**
         * @notice  We execute the seed steps, starting from the root step
         */
        uint256[] memory startingIndices = new uint256[](1);
        startingIndices[0] = 0;
        executeStepTree(SEED_STEPS, startingIndices, depositItem);
    }

    /**
     * @notice
     * handleWithdraw()
     * The actual withdraw execution handler
     * @param withdrawItem - OperationItem from the operations queue, representing the withdrawal request
     */
    function executeWithdraw(OperationItem memory withdrawItem) internal {
        /**
         * @dev At this point, we have deducted the shares from the user's balance and the total supply
         * when the request was made.
         */

        /**
         * Decode the first byte argument as an amount
         */
        uint256 amount = abi.decode(withdrawItem.arguments[0], (uint256));

        /**
         * The share in % this amount represnets of the total shares (Plus the amount b4 dividing, since we already deducted from it in the initial function)
         */
        uint256 shareOfVaultInPercentage = (totalShares + amount) / amount;

        assembly {
            // We MSTORE at the withdraw share memory location the % share of the withdraw amount of the total vault, times 100
            // (e.g, 100 shares to withdraw, 1000 total shares = 1000 / 100 * 100(%) = 1000 (10% multipled by 100, for safe maths...))
            mstore(
                WITHDRAW_SHARES_MEM_LOCATION,
                mul(shareOfVaultInPercentage, 100)
            )
            // Update the free mem pointer (we know it in advanced no need to mload on existing stored ptr)
            mstore(0x40, add(WITHDRAW_SHARES_MEM_LOCATION, 0x20))
        }

        /**
         * @notice We keep track of what the deposit token balance was prior to the execution
         */
        uint256 preVaultBalance = DEPOSIT_TOKEN.balanceOf(address(this));

        /**
         * @notice  We begin executing the uproot (reverse) steps
         */
        uint256[] memory startingIndices = new uint256[](1);
        startingIndices[0] = 0;
        executeStepTree(UPROOTING_STEPS, startingIndices, withdrawItem);

        /**
         * @notice We check to see if our state is currently locked. If it isn't, it means
         * the last step executed successfully and unlocked the state, and we can complete the operation by dequeuing it.
         * Otherwise, it means we have not yet completed the operation (offchain break), and we do not dequeue it;
         * The queue item will be re-accessed from the queue in storage, and probably we will be inputted an additional
         * fullfill command to input to the ``executeStepTree()`` function.
         */
        // if (!locked) dequeueOp();

        /**
         * After executing all of the steps, we get the balance difference,
         * and transfer to the user.
         * We use safeERC20, so if the debt is 0, the execution reverts.
         * We also deduct the shares from the user's balance, and from the total shares supply
         */
        uint256 debt = DEPOSIT_TOKEN.balanceOf(address(this)) - preVaultBalance;
        DEPOSIT_TOKEN.safeTransfer(withdrawItem.initiator, debt);
    }

    /**
     * @notice
     * handleRunStrategy()
     * Handles a strategy run request
     */
    function executeStrategy(OperationItem memory strategyRunRequest) internal {
        /**
         * Execute the strategy's tree of steps with the provided startingIndices and fullfill command
         */
        uint256[] memory startingIndices = new uint256[](1);
        startingIndices[0] = 0;
        executeStepTree(STEPS, startingIndices, strategyRunRequest);
    }

    // ==============================
    //        STEPS EXECUTION
    // ==============================
    /**
     * @notice
     * executeStepTree()
     * Accepts a linked-list (array) of YCStep, and a starting index to begin executing.
     * Note this function is recursive - It executes a step, then all of it's children, then all of their children, etc.
     *
     * @param virtualTree - A linked list array of YCSteps to execute
     * @param startingIndices - An array of indicies of the steps to begin executing the tree from
     */
    function executeStepTree(
        bytes[] memory virtualTree,
        uint256[] memory startingIndices,
        OperationItem memory operationRequest
    ) public onlyDiamond {
        /**
         * Iterate over each one of the starting indices
         */
        for (uint256 i = 0; i < startingIndices.length; i++) {
            /**
             * Load the current virtualTree step index
             */
            uint256 stepIndex = startingIndices[i];

            /**
             * Begin by retreiving & decoding the current YC step from the virtual tree
             */
            YCStep memory step = abi.decode(virtualTree[stepIndex], (YCStep));

            /**
             * @notice Initiating a variable for the "chosenOffspringIdx", which is ONLY RELEVENT
             * for conditional steps.
             *
             * When a conditional step runs, it will reassign to this variable either:
             * - An index of one of it's children
             * - 0
             * If it's an index of one of it's children, it means that it found a case where
             * one of it's children conditions returned true, and we should only execute it (rather than all of it's children indexes).
             * Otherwise, if the index is 0, it means it did not find any, and we should not execute any of it's children.
             * (It is impossible for a condition index to be 0, since it will always be the root)
             */
            uint256 chosenOffspringIdx;

            /**
             * Check to see if current step is a condition - Execute the conditional function with it's children if it is.
             */
            if (step.conditions.length > 0) {
                // Sufficient check to make sure there are as many conditions as there are children
                require(
                    step.conditions.length == step.childrenIndices.length,
                    "Conditions & Children Mismatch"
                );

                // Assign to the chosenOffspringIdx variable the return value from the conditional checker
                chosenOffspringIdx = _determineConditions(step.conditions);
            }

            /**
             * We first check to see if this step is a callback step.
             */
            if (step.isCallback) {
                /**
                 * @notice @dev
                 * A callback step means it requires offchain-computed data to be used.
                 * When the initial request for this operation run was made, it was re-entered with the offchain-computed data,
                 * and set on our operation item in an array of YC commands.
                 * We check to see if, at our (step) index, the command calldata exists. If it does, we run it.
                 * Otherwise, we check to see if we are on mainnet currently. If we are, it means something is wrong, and we shall revert.
                 * If we are on a fork, we emit a "RequestFullfill" event. Which will be used by the offchain simulator to create the command calldata,
                 * which we should have on every mainnet execution for callback steps.
                 */
                if (
                    bytes32(operationRequest.commandCalldatas[stepIndex]) !=
                    bytes32(0)
                )
                    _runFunction(operationRequest.commandCalldatas[stepIndex]);

                    // Revert if we are on mainnet
                else if (isMainnet) revert NoOffchainComputedCommand(stepIndex);
                // Emit a fullfill event otherwise
                else emit RequestFullfill(stepIndex, step.func);
            }
            /**
             * If the step is not a callback (And also not empty), we execute the step's function
             */
            else if (bytes32(step.func) != bytes32(0)) _runFunction(step.func);

            /**
             * @notice
             * At this point, we move onto executing the step's children.
             * If the chosenOffSpringIdx variable does not equal to 0, we execute the children idx at that index
             * of the array of indexes of the step. So if the index 2 was returnd, we execute virtualTree[step.childrenIndices[2]].
             * Otherwise, we do a full iteration over all children
             */

            // We initiatre this array to a length of 1. If we should execute all children, this is reassigned to.
            uint256[] memory childrenStartingIndices = new uint256[](1);

            // If offspring idx is valid, we assign to index 0 it's index
            if (chosenOffspringIdx > 0)
                childrenStartingIndices[0] = step.childrenIndices[
                    // Note we -1 here, since the chosenOffspringIdx would have upped it up by 1 (to retain 0 as the falsy indicator)
                    chosenOffspringIdx - 1
                ];

                // Else it equals to all of the step's children
            else childrenStartingIndices = step.childrenIndices;

            /**
             * We now iterate over each children and @recruse the function call
             * Note that the executeStepTree() function accepts an array of steps to execute.
             * You may would have expected us to do an iteration over each child, but in order to be complied with
             * the fact that, an execution tree may emit multiple offchain requests in a single transaction - We accept an array
             * of starting indices, rather than a single starting index. (Offchain actions will be batched per transaction and executed together here,
             * rather than per-event).
             */
            executeStepTree(
                virtualTree,
                childrenStartingIndices,
                operationRequest
            );
        }
    }
}

