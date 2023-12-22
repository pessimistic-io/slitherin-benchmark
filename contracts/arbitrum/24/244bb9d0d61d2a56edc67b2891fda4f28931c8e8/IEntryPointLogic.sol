// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IEntryPointLogic - EntryPointLogic Interface
/// @dev This contract provides functions for adding automation workflows,
/// interacting with Gelato logic, activating and deactivating vaults
/// and workflows and checking vault status.
interface IEntryPointLogic {
    // =========================
    // Storage
    // =========================

    /// @notice Data structure representing EntryPoint storage elements.
    struct EntryPointStorage {
        mapping(uint256 => Workflow) workflows;
        mapping(uint256 => bytes32) tasks;
        // a counter for generating unique keys for workflows.
        uint128 workflowKeys;
        // a boolean that indicates if the entire `EntryPoint` logic is inactive.
        bool inactive;
    }

    /// @notice Data structure representing Checker elements.
    struct Checker {
        // the data which is used to check the condition and rewrite storage (if necessary).
        bytes data;
        // the data which only is used to check the condition.
        bytes viewData;
        // the data from which a unique storage pointer for the checker is derived.
        // pointer = keccak256(storageRef).
        bytes storageRef;
        // Initial data, which is called during workflow adding.
        // Not stored in the storage.
        bytes initData;
    }

    /// @notice Data structure representing Action elements.
    struct Action {
        // the data which is used to perform the action.
        bytes data;
        // the data from which a unique storage pointer for the action is derived.
        // pointer = keccak256(storageRef).
        bytes storageRef;
        // Initial data, which is called during workflow adding.
        // Not stored in the storage.
        bytes initData;
    }

    /// @notice Data structure representing Workflow elements.
    struct Workflow {
        Checker[] checkers;
        Action[] actions;
        address executor;
        uint88 counter;
        bool inactive;
    }

    // =========================
    // Events
    // =========================

    /// @notice Emits when EntryPoint is run.
    /// @param executor Address of the executor.
    event EntryPointRun(address indexed executor, uint256 workflowKey);

    /// @notice Emits when EntryPoint is run via Gelato.
    event EntryPointRunGelato(uint256 workflowKey);

    /// @notice Emits when EntryPoint vault is activated.
    event EntryPointVaultStatusActivated();

    /// @notice Emits when EntryPoint vault is deactivated.
    event EntryPointVaultStatusDeactivated();

    /// @notice Emits when a workflow is activated.
    /// @param workflowKey Key of the activated workflow.
    event EntryPointWorkflowStatusActivated(uint256 workflowKey);

    /// @notice Emits when a workflow is deactivated.
    /// @param workflowKey Key of the deactivated workflow.
    event EntryPointWorkflowStatusDeactivated(uint256 workflowKey);

    /// @notice Emits when a workflow is added.
    /// @param workflowKey Key of the added workflow.
    event EntryPointAddWorkflow(uint256 workflowKey);

    /// @notice Emits when a Gelato task is created.
    /// @param workflowKey Key of the associated workflow.
    /// @param id Identifier of the created task.
    event GelatoTaskCreated(uint256 workflowKey, bytes32 id);

    /// @notice Emits when a Gelato task is cancelled.
    /// @param workflowKey Key of the associated workflow.
    /// @param id Identifier of the cancelled task.
    event GelatoTaskCancelled(uint256 workflowKey, bytes32 id);

    // =========================
    // Errors
    // =========================

    /// @dev Thrown when trying to activate vault or workflow that is already active.
    error EntryPoint_AlreadyActive();

    /// @dev Thrown when trying to deactivate vault or workflow that is already inactive.
    error EntryPoint_AlreadyInactive();

    /// @dev Thrown when attempting an operation that requires the vault to be active.
    error EntryPoint_VaultIsInactive();

    /// @dev Thrown when attempting an operation that requires the workflow to be active.
    error EntryPoint_WorkflowIsInactive();

    /// @dev Thrown when trigger verification fails during the workflow execution.
    error EntryPoint_TriggerVerificationFailed();

    /// @dev Thrown when trying to access a workflow that doesn't exist.
    error EntryPoint_WorkflowDoesNotExist();

    /// @dev Thrown when attempting to start a Gelato task that has already been started.
    error Gelato_TaskAlreadyStarted();

    /// @dev Thrown when attempting to cancel a Gelato task that doesn't exist.
    error Gelato_CannotCancelTaskWhichNotExists();

    /// @dev Thrown when the message sender is not the dedicated Gelato address.
    error Gelato_MsgSenderIsNotDedicated();

    // =========================
    // Status methods
    // =========================

    /// @notice Activates the vault.
    /// @param callbacks An array of callbacks to be executed during activation.
    /// @dev Callbacks can be used for various tasks like adding workflows or adding native balance to the vault.
    function activateVault(bytes[] calldata callbacks) external;

    /// @notice Deactivates the vault.
    /// @param callbacks An array of callbacks to be executed during deactivation.
    /// @dev Callbacks can be used for various tasks like cancel task or removing native balance from the vault.
    function deactivateVault(bytes[] calldata callbacks) external;

    /// @notice Activates a specific workflow.
    /// @param workflowKey The identifier of the workflow to be activated.
    function activateWorkflow(uint256 workflowKey) external;

    /// @notice Deactivates a specific workflow.
    /// @param workflowKey The identifier of the workflow to be deactivated.
    function deactivateWorkflow(uint256 workflowKey) external;

    /// @notice Checks if the vault is active.
    /// @return active Returns true if the vault is active, otherwise false.
    function isActive() external view returns (bool active);

    // =========================
    // Actions with workflows
    // =========================

    /// @notice Adds a new workflow to the EntryPoint and creates a Gelato task for it.
    /// @param checkers An array of Checker structures to define the conditions.
    /// @param actions An array of Action structures to define the actions.
    /// @param executor The address of the executor.
    /// @param count The number of times the workflow should be executed.
    function addWorkflowAndGelatoTask(
        Checker[] calldata checkers,
        Action[] calldata actions,
        address executor,
        uint88 count
    ) external;

    /// @notice Adds a new workflow to the EntryPoint.
    /// @param checkers An array of Checker structures to define the conditions.
    /// @param actions An array of Action structures to define the actions.
    /// @param executor The address of the executor.
    /// @param count The number of times the workflow should be executed.
    function addWorkflow(
        Checker[] calldata checkers,
        Action[] calldata actions,
        address executor,
        uint88 count
    ) external;

    /// @notice Fetches the details of a specific workflow.
    /// @param workflowKey The identifier of the workflow.
    /// @return Workflow structure containing the details of the workflow.
    function getWorkflow(
        uint256 workflowKey
    ) external view returns (Workflow memory);

    /// @notice Retrieves the next available workflow key.
    /// @return The next available workflow key.
    function getNextWorkflowKey() external view returns (uint256);

    // =========================
    // Main Logic
    // =========================

    /// @notice Checks if a workflow can be executed.
    /// @param workflowKey The identifier of the workflow.
    /// @return A boolean indicating if the workflow can be executed,
    /// and the encoded data to run the workflow on Gelato.
    function canExecWorkflowCheck(
        uint256 workflowKey
    ) external view returns (bool, bytes memory);

    /// @notice Executes a specific workflow and compensates the `feeReceiver` for gas costs.
    /// @param workflowKey Unique identifier for the workflow to be executed.
    function run(uint256 workflowKey) external;

    /// @notice Executes the logic of a workflow via Gelato.
    /// @param workflowKey The identifier of the workflow to be executed.
    /// @dev Only a dedicated message sender from Gelato can call this function.
    function runGelato(uint256 workflowKey) external;

    // =========================
    // Gelato logic
    // =========================

    /// @notice Fetches the dedicated message sender for Gelato.
    /// @return The address of the dedicated message sender.
    function dedicatedMessageSender() external view returns (address);

    /// @notice Creates a task in Gelato associated with a specific workflow.
    /// @param workflowKey The identifier of the workflow for which the task is created.
    /// @return Identifier of the created task.
    function createTask(uint256 workflowKey) external payable returns (bytes32);

    /// @notice Cancels an existing Gelato task.
    /// @param workflowKey Unique identifier for the workflow associated with the task.
    /// @dev Reverts if the task is not existent.
    function cancelTask(uint256 workflowKey) external;

    /// @notice Retrieves the `taskId` for a specific workflow.
    /// @param workflowKey Unique identifier for the workflow.
    /// @return The taskId associated with the workflow.
    function getTaskId(uint256 workflowKey) external view returns (bytes32);
}

