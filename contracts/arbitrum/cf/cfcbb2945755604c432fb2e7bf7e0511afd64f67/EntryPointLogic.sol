// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {IAutomate, ModuleData, Module, IOpsProxyFactory} from "./Types.sol";

import {DittoFeeBase, IProtocolFees} from "./DittoFeeBase.sol";
import {BaseContract, Constants} from "./BaseContract.sol";
import {TransferHelper} from "./TransferHelper.sol";

import {IAccessControlLogic} from "./IAccessControlLogic.sol";
import {IEntryPointLogic} from "./IEntryPointLogic.sol";

/// @title EntryPointLogic
contract EntryPointLogic is IEntryPointLogic, BaseContract, DittoFeeBase {
    // =========================
    // Constructor
    // =========================

    /// @dev The instance of the GelatoAutomate contract.
    IAutomate internal immutable _automate;

    /// @dev The address of the Gelato main contract.
    address private immutable _gelato;

    /// @dev A constant address pointing to the OpsProxyFactory contract
    /// for Gelato proxy deployment.
    IOpsProxyFactory private constant OPS_PROXY_FACTORY =
        IOpsProxyFactory(0xC815dB16D4be6ddf2685C201937905aBf338F5D7);

    /// @notice Sets the addresses of the `automate` and `gelato` upon deployment.
    /// @param automate The instance of GelatoAutomate contract.
    /// @param gelato The address of the Gelato main contract.
    constructor(
        IAutomate automate,
        address gelato,
        IProtocolFees protocolFees
    ) DittoFeeBase(protocolFees) {
        _automate = automate;
        _gelato = gelato;
    }

    // =========================
    // Storage
    // =========================

    /// @dev Storage position for the entry point logic, to avoid collisions in storage.
    /// @dev Uses the "magic" constant to find a unique storage slot.
    bytes32 private immutable ENTRY_POINT_LOGIC_STORAGE_POSITION =
        keccak256("vault.workflow.entrypointlogic.storage");

    /// @dev Returns the storage slot for the entry point logic.
    /// @dev This function utilizes inline assembly to directly access the desired storage position.
    ///
    /// @return eps The storage slot pointer for the entry point logic.
    function _getLocalStorage()
        internal
        view
        returns (EntryPointStorage storage eps)
    {
        bytes32 position = ENTRY_POINT_LOGIC_STORAGE_POSITION;
        assembly ("memory-safe") {
            eps.slot := position
        }
    }

    // =========================
    // Status methods
    // =========================

    /// @inheritdoc IEntryPointLogic
    function activateVault(
        bytes[] calldata callbacks
    ) external onlyOwnerOrVaultItself {
        EntryPointStorage storage eps = _getLocalStorage();
        if (!eps.inactive) {
            revert EntryPoint_AlreadyActive();
        }

        eps.inactive = false;
        _callback(callbacks);

        emit EntryPointVaultStatusActivated();
    }

    /// @inheritdoc IEntryPointLogic
    function deactivateVault(
        bytes[] calldata callbacks
    ) external onlyOwnerOrVaultItself {
        EntryPointStorage storage eps = _getLocalStorage();
        if (eps.inactive) {
            revert EntryPoint_AlreadyInactive();
        }

        eps.inactive = true;
        _callback(callbacks);

        emit EntryPointVaultStatusDeactivated();
    }

    /// @inheritdoc IEntryPointLogic
    function activateWorkflow(
        uint256 workflowKey
    ) external onlyOwnerOrVaultItself {
        EntryPointStorage storage eps = _getLocalStorage();
        _verifyWorkflowKey(eps, workflowKey);

        Workflow storage workflow = eps.workflows[workflowKey];
        if (!workflow.inactive) {
            revert EntryPoint_AlreadyActive();
        }

        workflow.inactive = false;

        emit EntryPointWorkflowStatusActivated(workflowKey);
    }

    /// @inheritdoc IEntryPointLogic
    function deactivateWorkflow(
        uint256 workflowKey
    ) external onlyOwnerOrVaultItself {
        EntryPointStorage storage eps = _getLocalStorage();
        _verifyWorkflowKey(eps, workflowKey);

        Workflow storage workflow = eps.workflows[workflowKey];
        if (workflow.inactive) {
            revert EntryPoint_AlreadyInactive();
        }

        _deactivateWorkflow(workflowKey, workflow);
    }

    /// @inheritdoc IEntryPointLogic
    function isActive() external view returns (bool active) {
        return !_getLocalStorage().inactive;
    }

    // =========================
    // Actions with workflows
    // =========================

    /// @inheritdoc IEntryPointLogic
    function addWorkflowAndGelatoTask(
        Checker[] calldata checkers,
        Action[] calldata actions,
        address executor,
        uint88 count
    ) external onlyVaultItself {
        EntryPointStorage storage eps = _getLocalStorage();

        // starts from zero
        uint128 workflowKey;
        unchecked {
            workflowKey = eps.workflowKeys++;
        }

        _addWorkflow(checkers, actions, executor, count, workflowKey, eps);

        _createTask(eps, workflowKey);
    }

    /// @inheritdoc IEntryPointLogic
    function addWorkflow(
        Checker[] calldata checkers,
        Action[] calldata actions,
        address executor,
        uint88 count
    ) external onlyVaultItself {
        EntryPointStorage storage eps = _getLocalStorage();

        // starts from zero
        uint128 workflowKey;
        unchecked {
            workflowKey = eps.workflowKeys++;
        }

        _addWorkflow(checkers, actions, executor, count, workflowKey, eps);
    }

    /// @inheritdoc IEntryPointLogic
    function getWorkflow(
        uint256 workflowKey
    ) external view returns (Workflow memory) {
        return _getLocalStorage().workflows[workflowKey];
    }

    /// @inheritdoc IEntryPointLogic
    function getNextWorkflowKey() external view returns (uint256) {
        return _getLocalStorage().workflowKeys;
    }

    // =========================
    // Main Logic
    // =========================

    /// @inheritdoc IEntryPointLogic
    function canExecWorkflowCheck(
        uint256 workflowKey
    ) external view returns (bool, bytes memory) {
        // no check for inactive, not necessary
        Workflow storage workflow = _getLocalStorage().workflows[workflowKey];

        uint256 length = workflow.checkers.length;
        for (uint256 checkerId; checkerId < length; ) {
            Checker storage checker = workflow.checkers[checkerId];

            bytes memory data = checker.viewData;
            if (checker.storageRef.length > 0) {
                data = abi.encodePacked(data, keccak256(checker.storageRef));
            }

            (bool success, bytes memory returnData) = address(this).staticcall(
                data
            );

            // on successful call - check the return value from the checker
            if (success) {
                success = abi.decode(returnData, (bool));
                if (!success) {
                    return (false, bytes(""));
                }
            }

            unchecked {
                // increment loop counter
                ++checkerId;
            }
        }
        return (true, abi.encodeCall(this.runGelato, (workflowKey)));
    }

    /// @inheritdoc IEntryPointLogic
    function run(
        uint256 workflowKey
    ) external virtual onlyRoleOrOwner(Constants.EXECUTOR_ROLE) {
        uint256 gasUsed = gasleft();

        _run(workflowKey);

        emit EntryPointRun(msg.sender, workflowKey);

        unchecked {
            gasUsed = (gasUsed - gasleft()) * tx.gasprice;
        }

        _transferDittoFee(gasUsed, 0, false);
    }

    /// @inheritdoc IEntryPointLogic
    function runGelato(uint256 workflowKey) external {
        _onlyDedicatedMsgSender();

        _run(workflowKey);

        // Fetches the fee details from _automate during gelato automation process.
        (uint256 fee, ) = _automate.getFeeDetails();

        // feeToken is always Native currency
        // send fee to gelato
        TransferHelper.safeTransferNative(_gelato, fee);

        _transferDittoFee(fee, 0, false);

        emit EntryPointRunGelato(workflowKey);
    }

    // =========================
    // Gelato logic
    // =========================

    /// @inheritdoc IEntryPointLogic
    function dedicatedMessageSender() public view returns (address) {
        (address dedicatedMsgSender, ) = OPS_PROXY_FACTORY.getProxyOf(
            address(this)
        );
        return dedicatedMsgSender;
    }

    /// @inheritdoc IEntryPointLogic
    function createTask(
        uint256 workflowKey
    ) external payable onlyVaultItself returns (bytes32) {
        EntryPointStorage storage eps = _getLocalStorage();

        _verifyWorkflowKey(eps, workflowKey);

        if (eps.tasks[workflowKey] != bytes32(0)) {
            revert Gelato_TaskAlreadyStarted();
        }

        return _createTask(eps, workflowKey);
    }

    /// @inheritdoc IEntryPointLogic
    function cancelTask(uint256 workflowKey) external onlyOwnerOrVaultItself {
        EntryPointStorage storage eps = _getLocalStorage();

        if (eps.tasks[workflowKey] == bytes32(0)) {
            revert Gelato_CannotCancelTaskWhichNotExists();
        }

        _cancelTask(workflowKey, eps);
    }

    /// @inheritdoc IEntryPointLogic
    function getTaskId(uint256 workflowKey) external view returns (bytes32) {
        return _getLocalStorage().tasks[workflowKey];
    }

    // =========================
    // Private function
    // =========================

    /// @dev Executes the main logic of the workflow by provided `workflowKey`.
    /// @param workflowKey Identifier of the workflow to be executed.
    function _run(uint256 workflowKey) internal {
        EntryPointStorage storage eps = _getLocalStorage();

        _verifyWorkflowKey(eps, workflowKey);

        if (eps.inactive) {
            revert EntryPoint_VaultIsInactive();
        }

        Workflow storage workflow = eps.workflows[workflowKey];
        if (workflow.inactive) {
            revert EntryPoint_WorkflowIsInactive();
        }

        uint256 length = workflow.checkers.length;

        for (uint256 checkerId; checkerId < length; ) {
            Checker storage checker = workflow.checkers[checkerId];

            bytes memory data = checker.data;
            if (checker.storageRef.length > 0) {
                data = abi.encodePacked(data, keccak256(checker.storageRef));
            }

            (bool success, bytes memory returnData) = address(this).call(data);

            // on successful call - check the return value from the checker
            if (success) {
                success = abi.decode(returnData, (bool));
            }

            if (!success) {
                revert EntryPoint_TriggerVerificationFailed();
            }

            unchecked {
                // increment loop counter
                ++checkerId;
            }
        }

        length = workflow.actions.length;
        for (uint256 actionId; actionId < length; ) {
            Action storage action = workflow.actions[actionId];
            bytes memory data = action.data;
            if (action.storageRef.length > 0) {
                data = abi.encodePacked(data, keccak256(action.storageRef));
            }

            // call from address(this)
            (bool success, ) = address(this).call(data);

            if (!success) {
                // if call fails -> revert with original error message
                assembly ("memory-safe") {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }

            unchecked {
                // increment loop counter
                ++actionId;
            }
        }

        if (workflow.counter > 0) {
            uint256 counter;
            unchecked {
                counter = --workflow.counter;
            }

            if (counter == 0) {
                _deactivateWorkflow(workflowKey, workflow);

                if (eps.tasks[workflowKey] != bytes32(0)) {
                    _cancelTask(workflowKey, eps);
                }
            }
        }
    }

    /// @dev Internal callback function that iterates through and calls the provided `datas`.
    /// @param datas Array of data elements for callback.
    function _callback(bytes[] memory datas) private {
        if (datas.length > 0) {
            uint256 datasNumber = datas.length;
            for (uint256 callbackId; callbackId < datasNumber; ) {
                // delegatecall only from OWNER
                _call(datas[callbackId]);

                unchecked {
                    // increment loop counter
                    ++callbackId;
                }
            }
        }
    }

    /// @dev Calls initialization logic based on the provided `data` and `storageRef`.
    /// @param data Data to be used in the initialization.
    /// @param storageRef Storage reference associated with the data.
    function _initCall(bytes memory data, bytes memory storageRef) private {
        if (data.length > 0) {
            if (storageRef.length > 0) {
                data = abi.encodePacked(data, keccak256(storageRef));
            }

            _call(data);
        }
    }

    /// @dev Executes a delegate call with the given `data`.
    /// @param data Data to be used in the delegate call.
    function _call(bytes memory data) private {
        (bool success, bytes memory returnData) = address(this).call(data);
        if (!success) {
            // If call fails -> revert with original error message
            assembly ("memory-safe") {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    /// @dev Verifies if a given `workflowKey` exists in the EntryPoint storage.
    /// @param eps Reference to the EntryPoint storage structure.
    /// @param workflowKey Workflow key to verify.
    function _verifyWorkflowKey(
        EntryPointStorage storage eps,
        uint256 workflowKey
    ) private view {
        if (!(workflowKey < eps.workflowKeys)) {
            revert EntryPoint_WorkflowDoesNotExist();
        }
    }

    /// @dev Ensures that the current `msg.sender` is the dedicated sender from the Gelato.
    function _onlyDedicatedMsgSender() internal view {
        if (msg.sender != dedicatedMessageSender()) {
            revert Gelato_MsgSenderIsNotDedicated();
        }
    }

    /// @dev Returns a concatenated byte representation of the `resolverAddress` and `resolverData`.
    /// @param resolverAddress Address of the resolver.
    /// @param resolverData Associated data of the resolver.
    /// @return Returns a bytes memory combining the resolver address and data.
    function _resolverModuleArg(
        address resolverAddress,
        bytes memory resolverData
    ) internal pure returns (bytes memory) {
        return abi.encode(resolverAddress, resolverData);
    }

    /// @notice Adds a new workflow to the EntryPoint storage.
    /// @dev This function initializes checkers and actions, sets the executor and workflow counter,
    /// and grants the executor role.
    /// @param checkers Array of Checker structs to be added to the workflow.
    /// @param actions Array of Action structs to be added to the workflow.
    /// @param executor Address of the executor for the workflow.
    /// @param count The counter for the workflow.
    /// @param workflowKey Unique identifier for the workflow.
    /// @param eps Reference to EntryPointStorage where the workflow is to be added.
    function _addWorkflow(
        Checker[] calldata checkers,
        Action[] calldata actions,
        address executor,
        uint88 count,
        uint128 workflowKey,
        EntryPointStorage storage eps
    ) private {
        Workflow storage workflow = eps.workflows[workflowKey];

        uint256 length = checkers.length;
        for (uint i; i < length; ) {
            workflow.checkers.push();
            Checker storage checker = workflow.checkers[i];

            _initCall(checkers[i].initData, checkers[i].storageRef);
            checker.data = checkers[i].data;
            checker.viewData = checkers[i].viewData;
            if (checkers[i].storageRef.length > 0) {
                checker.storageRef = checkers[i].storageRef;
            }

            unchecked {
                // increment loop counter
                ++i;
            }
        }

        length = actions.length;
        for (uint i; i < length; ) {
            workflow.actions.push();
            Action storage action = workflow.actions[i];

            _initCall(actions[i].initData, actions[i].storageRef);
            action.data = actions[i].data;
            if (actions[i].storageRef.length > 0) {
                action.storageRef = actions[i].storageRef;
            }

            unchecked {
                // increment loop counter
                ++i;
            }
        }

        workflow.executor = executor;
        if (count > 0) {
            workflow.counter = count;
        }

        _call(
            abi.encodeCall(
                IAccessControlLogic.grantRole,
                (Constants.EXECUTOR_ROLE, executor)
            )
        );

        emit EntryPointAddWorkflow(workflowKey);
    }

    /// @notice Creates a new task in the EntryPoint storage.
    /// @dev This function sets up the modules and arguments for the task,
    /// then calls the automation logic to create the task.
    /// @param eps Reference to EntryPointStorage where the task data to be stored.
    /// @param workflowKey Unique identifier for the associated workflow.
    /// @return taskId The unique identifier for the created task.
    function _createTask(
        EntryPointStorage storage eps,
        uint256 workflowKey
    ) private returns (bytes32) {
        ModuleData memory moduleData = ModuleData({
            modules: new Module[](2),
            args: new bytes[](2)
        });

        moduleData.modules[0] = Module.RESOLVER;
        moduleData.modules[1] = Module.PROXY;

        moduleData.args[0] = _resolverModuleArg(
            address(this),
            abi.encodeWithSelector(
                this.canExecWorkflowCheck.selector,
                workflowKey
            )
        );

        bytes memory execData = abi.encodeWithSelector(
            this.runGelato.selector,
            workflowKey
        );

        bytes32 taskId = _automate.createTask(
            address(this),
            execData,
            moduleData,
            Constants.ETH
        );

        // Set storage
        eps.tasks[workflowKey] = taskId;

        emit GelatoTaskCreated(workflowKey, taskId);

        return taskId;
    }

    /// @notice Cancels an existing task in the EntryPoint storage.
    /// @dev This function deletes the task from storage and then calls the automation logic to cancel the task.
    /// @param workflowKey Unique identifier for the associated workflow.
    /// @param eps Reference to EntryPointStorage where the task is stored.
    function _cancelTask(
        uint256 workflowKey,
        EntryPointStorage storage eps
    ) private {
        bytes32 taskId = eps.tasks[workflowKey];

        delete eps.tasks[workflowKey];

        _automate.cancelTask(taskId);

        emit GelatoTaskCancelled(workflowKey, taskId);
    }

    /// @notice Deactivates a workflow in the EntryPoint storage.
    /// @dev This function sets the inactive flag for a workflow to true.
    /// @param workflowKey Unique identifier for the workflow to be deactivated.
    /// @param workflow Reference to the Workflow storage to be deactivated.
    function _deactivateWorkflow(
        uint256 workflowKey,
        Workflow storage workflow
    ) private {
        workflow.inactive = true;

        emit EntryPointWorkflowStatusDeactivated(workflowKey);
    }
}

