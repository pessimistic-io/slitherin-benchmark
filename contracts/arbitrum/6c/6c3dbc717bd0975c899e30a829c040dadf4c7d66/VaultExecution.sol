/**
 * The execution functions for the vault (Internal/Used by YC Diamond)
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// ===============
//    IMPORTS
// ===============
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import "./VM.sol";
import "./OperationsQueue.sol";
import "./State.sol";
import "./vm_Constants.sol";
import "./ITokenStash.sol";
import "./VaultUtilities.sol";
import "./console.sol";

abstract contract VaultExecution is
    YCVM,
    OperationsQueue,
    VaultUtilities,
    VaultConstants,
    VaultState
{
    // Libs
    using SafeERC20 for IERC20;

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

        require(!operation.executed, "Operation Already Executed");

        // We lock the contract state
        locked = true;

        /**
         * We hydrate it with the command calldatas
         */
        operation.commandCalldatas = commandCalldatas;

        uint256[] memory startingIndices = new uint256[](1);
        startingIndices[0] = 0;

        /**
         * Switch statement for the operation to run
         */
        if (operation.action == ExecutionTypes.SEED)
            executeDeposit(operation, startingIndices);
        else if (operation.action == ExecutionTypes.UPROOT)
            executeWithdraw(operation, startingIndices);
        else if (operation.action == ExecutionTypes.TREE)
            executeStrategy(operation, startingIndices);
        else revert();

        // We unlock the contract state once the operation has completed
        operationRequests[operationIndex].executed = true;
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
    function executeDeposit(
        OperationItem memory depositItem,
        uint256[] memory startingIndices
    ) internal {
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
        executeStepTree(SEED_STEPS, startingIndices, depositItem);
    }

    /**
     * @notice
     * handleWithdraw()
     * The actual withdraw execution handler
     * @param withdrawItem - OperationItem from the operations queue, representing the withdrawal request
     */
    function executeWithdraw(
        OperationItem memory withdrawItem,
        uint256[] memory startingIndices
    ) internal {
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
        executeStepTree(UPROOTING_STEPS, startingIndices, withdrawItem);

        /**
         * After executing all of the steps, we get the balance difference,
         * and transfer to the user.
         * We use safeERC20, so if the debt is 0, the execution reverts.
         */
        uint256 debt = DEPOSIT_TOKEN.balanceOf(address(this)) - preVaultBalance;
        DEPOSIT_TOKEN.safeTransfer(withdrawItem.initiator, debt);
    }

    /**
     * @notice
     * handleRunStrategy()
     * Handles a strategy run request
     */
    function executeStrategy(
        OperationItem memory strategyRunRequest,
        uint256[] memory startingIndices
    ) internal {
        /**
         * Execute the strategy's tree of steps with the provided startingIndices and fullfill command
         */
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
    ) internal {
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
                    operationRequest.commandCalldatas.length > stepIndex &&
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

    // =========================
    //    SIMULATION METHODS
    // =========================
    //------------------
    // @notice ONLY ON FORKS, IRRELEVENT ON MAINNETS
    //------------------

    /**
     * @dev
     * ONLY ON FORK!!
     * set fork status
     */
    function setForkStatus() external {
        require(msg.sender == address(0), "Only Fork Address Can Do This");
        isMainnet = false;
    }

    /**
     * @dev
     * ONLY ON FORK!!
     * Used for simulating the run
     * @param operationIdx - The idx of the operation to simulate
     * @param startingIndices - The starting indices
     * @param commandsHydratedThusFar - Commands that were hydrated thus far
     */
    function simulateOperationHydrationAndExecution(
        uint256 operationIdx,
        uint256[] memory startingIndices,
        bytes[] memory commandsHydratedThusFar
    ) external {
        require(msg.sender == address(0), "Only Fork Address Can Do This");
        OperationItem memory operation = operationRequests[operationIdx];

        /**
         * We hydrate it with the command calldatas
         */
        operation.commandCalldatas = commandsHydratedThusFar;

        /**
         * Switch statement for the operation to run
         */
        if (operation.action == ExecutionTypes.SEED)
            executeDeposit(operation, startingIndices);
        else if (operation.action == ExecutionTypes.UPROOT)
            executeWithdraw(operation, startingIndices);
        else if (operation.action == ExecutionTypes.TREE)
            executeStrategy(operation, startingIndices);
        else revert();
    }
}

