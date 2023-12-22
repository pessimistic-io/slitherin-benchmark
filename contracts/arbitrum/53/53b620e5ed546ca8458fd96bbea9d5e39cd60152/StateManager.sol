// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IEpochsManager} from "./IEpochsManager.sol";
import {GovernanceMessageHandler} from "./GovernanceMessageHandler.sol";
import {IPRouter} from "./IPRouter.sol";
import {IPToken} from "./IPToken.sol";
import {IPFactory} from "./IPFactory.sol";
import {IStateManager} from "./IStateManager.sol";
import {IPReceiver} from "./IPReceiver.sol";
import {Roles} from "./Roles.sol";
import {Errors} from "./Errors.sol";
import {Constants} from "./Constants.sol";
import {Utils} from "./Utils.sol";
import {Network} from "./Network.sol";

contract StateManager is IStateManager, GovernanceMessageHandler, ReentrancyGuard {
    mapping(bytes32 => Action) private _operationsRelayerQueueAction;
    mapping(bytes32 => Action) private _operationsGovernanceCancelAction;
    mapping(bytes32 => Action) private _operationsGuardianCancelAction;
    mapping(bytes32 => Action) private _operationsSentinelCancelAction;
    mapping(bytes32 => Action) private _operationsExecuteAction;
    mapping(bytes32 => uint8) private _operationsTotalCancelActions;
    mapping(bytes32 => bytes1) private _operationsStatus;
    mapping(uint16 => bytes32) private _epochsSentinelsRoot;

    address public immutable factory;
    address public immutable epochsManager;
    uint32 public immutable baseChallengePeriodDuration;
    uint16 public immutable kChallengePeriod;
    uint16 public immutable maxOperationsInQueue;

    // bytes32 public guardiansRoot;
    uint256 public lockedAmountChallengePeriod;
    uint16 public numberOfOperationsInQueue;

    modifier onlySentinel(bytes calldata proof, string memory action) {
        _;
    }

    modifier onlyGuardian(bytes calldata proof, string memory action) {
        // TODO: check if msg.sender is a guardian
        _;
    }

    modifier onlyGovernance(bytes calldata proof, string memory action) {
        // TODO: check if msg.sender is a governance
        _;
    }

    modifier onlyWhenIsNotInLockDown(bool addMaxChallengePeriodDuration) {
        uint16 currentEpoch = IEpochsManager(epochsManager).currentEpoch();
        if (_epochsSentinelsRoot[currentEpoch] == bytes32(0)) {
            revert Errors.LockDown();
        }

        uint256 epochDuration = IEpochsManager(epochsManager).epochDuration();
        uint256 startFirstEpochTimestamp = IEpochsManager(epochsManager).startFirstEpochTimestamp();
        uint256 currentEpochEndTimestamp = startFirstEpochTimestamp + ((currentEpoch + 1) * epochDuration);

        // If a relayer queues a malicious operation shortly before lockdown mode begins, what happens?
        // When lockdown mode is initiated, both sentinels and guardians lose their ability to cancel operations.
        // Consequently, the malicious operation may be executed immediately after the lockdown period ends,
        // especially if the operation's queue time is significantly shorter than the lockdown duration.
        // To mitigate this risk, operations should not be queued if the max challenge period makes
        // the operation challenge period finish after 1 hour before the end of an epoch.
        if (
            block.timestamp +
                (
                    addMaxChallengePeriodDuration
                        ? baseChallengePeriodDuration +
                            (maxOperationsInQueue * maxOperationsInQueue * kChallengePeriod) -
                            kChallengePeriod
                        : 0
                ) >=
            currentEpochEndTimestamp - 3600
        ) {
            revert Errors.LockDown();
        }

        _;
    }

    constructor(
        address factory_,
        uint32 baseChallengePeriodDuration_,
        address epochsManager_,
        address telepathyRouter,
        address governanceMessageVerifier,
        uint32 allowedSourceChainId,
        uint256 lockedAmountChallengePeriod_,
        uint16 kChallengePeriod_,
        uint16 maxOperationsInQueue_
    ) GovernanceMessageHandler(telepathyRouter, governanceMessageVerifier, allowedSourceChainId) {
        factory = factory_;
        epochsManager = epochsManager_;
        baseChallengePeriodDuration = baseChallengePeriodDuration_;
        lockedAmountChallengePeriod = lockedAmountChallengePeriod_;
        kChallengePeriod = kChallengePeriod_;
        maxOperationsInQueue = maxOperationsInQueue_;
    }

    /// @inheritdoc IStateManager
    function challengePeriodOf(Operation calldata operation) public view returns (uint64, uint64) {
        bytes32 operationId = operationIdOf(operation);
        bytes1 operationStatus = _operationsStatus[operationId];
        return _challengePeriodOf(operationId, operationStatus);
    }

    function getCurrentChallengePeriodDuration() public view returns (uint64) {
        uint32 localNumberOfOperationsInQueue = numberOfOperationsInQueue;
        if (localNumberOfOperationsInQueue == 0) return baseChallengePeriodDuration;

        return
            baseChallengePeriodDuration +
            (localNumberOfOperationsInQueue * localNumberOfOperationsInQueue * kChallengePeriod) -
            kChallengePeriod;
    }

    /// @inheritdoc IStateManager
    function getSentinelsRootForEpoch(uint16 epoch) external view returns (bytes32) {
        return _epochsSentinelsRoot[epoch];
    }

    /// @inheritdoc IStateManager
    function operationIdOf(Operation calldata operation) public pure returns (bytes32) {
        return
            sha256(
                abi.encode(
                    operation.originBlockHash,
                    operation.originTransactionHash,
                    operation.originNetworkId,
                    operation.nonce,
                    operation.destinationAccount,
                    operation.destinationNetworkId,
                    operation.underlyingAssetName,
                    operation.underlyingAssetSymbol,
                    operation.underlyingAssetDecimals,
                    operation.underlyingAssetTokenAddress,
                    operation.underlyingAssetNetworkId,
                    operation.assetAmount,
                    operation.userData,
                    operation.optionsMask
                )
            );
    }

    /// @inheritdoc IStateManager
    function protocolGuardianCancelOperation(
        Operation calldata operation,
        bytes calldata proof
    ) external onlyWhenIsNotInLockDown(false) onlyGuardian(proof, "cancel") {
        _protocolCancelOperation(operation, Actor.Guardian);
    }

    /// @inheritdoc IStateManager
    function protocolGovernanceCancelOperation(
        Operation calldata operation,
        bytes calldata proof
    ) external onlyGovernance(proof, "cancel") {
        _protocolCancelOperation(operation, Actor.Governance);
    }

    /// @inheritdoc IStateManager
    function protocolSentinelCancelOperation(
        Operation calldata operation,
        bytes calldata proof
    ) external onlyWhenIsNotInLockDown(false) onlySentinel(proof, "cancel") {
        _protocolCancelOperation(operation, Actor.Sentinel);
    }

    /// @inheritdoc IStateManager
    function protocolExecuteOperation(
        Operation calldata operation
    ) external payable onlyWhenIsNotInLockDown(false) nonReentrant {
        bytes32 operationId = operationIdOf(operation);

        bytes1 operationStatus = _operationsStatus[operationId];
        if (operationStatus == Constants.OPERATION_EXECUTED) {
            revert Errors.OperationAlreadyExecuted(operation);
        } else if (operationStatus == Constants.OPERATION_CANCELLED) {
            revert Errors.OperationAlreadyCancelled(operation);
        } else if (operationStatus == Constants.OPERATION_NULL) {
            revert Errors.OperationNotQueued(operation);
        }

        (uint64 startTimestamp, uint64 endTimestamp) = _challengePeriodOf(operationId, operationStatus);
        if (uint64(block.timestamp) < endTimestamp) {
            revert Errors.ChallengePeriodNotTerminated(startTimestamp, endTimestamp);
        }

        address destinationAddress = Utils.parseAddress(operation.destinationAccount);
        if (operation.assetAmount > 0) {
            address pTokenAddress = IPFactory(factory).getPTokenAddress(
                operation.underlyingAssetName,
                operation.underlyingAssetSymbol,
                operation.underlyingAssetDecimals,
                operation.underlyingAssetTokenAddress,
                operation.underlyingAssetNetworkId
            );
            IPToken(pTokenAddress).stateManagedProtocolMint(destinationAddress, operation.assetAmount);

            if (Utils.isBitSet(operation.optionsMask, 0)) {
                if (!Network.isCurrentNetwork(operation.underlyingAssetNetworkId)) {
                    revert Errors.InvalidNetwork(operation.underlyingAssetNetworkId);
                }
                IPToken(pTokenAddress).stateManagedProtocolBurn(destinationAddress, operation.assetAmount);
            }
        }

        if (operation.userData.length > 0) {
            if (destinationAddress.code.length == 0) revert Errors.NotContract(destinationAddress);
            try IPReceiver(destinationAddress).receiveUserData(operation.userData) {} catch {}
        }

        _operationsStatus[operationId] = Constants.OPERATION_EXECUTED;
        _operationsExecuteAction[operationId] = Action(_msgSender(), uint64(block.timestamp));

        Action storage queuedAction = _operationsRelayerQueueAction[operationId];
        (bool sent, ) = queuedAction.actor.call{value: lockedAmountChallengePeriod}("");
        if (!sent) {
            revert Errors.CallFailed();
        }

        unchecked {
            --numberOfOperationsInQueue;
        }
        emit OperationExecuted(operation);
    }

    /// @inheritdoc IStateManager
    function protocolQueueOperation(Operation calldata operation) external payable onlyWhenIsNotInLockDown(true) {
        uint256 expectedLockedAmountChallengePeriod = lockedAmountChallengePeriod;
        if (msg.value != expectedLockedAmountChallengePeriod) {
            revert Errors.InvalidLockedAmountChallengePeriod(msg.value, expectedLockedAmountChallengePeriod);
        }

        if (numberOfOperationsInQueue >= maxOperationsInQueue) {
            revert Errors.QueueFull();
        }

        bytes32 operationId = operationIdOf(operation);

        bytes1 operationStatus = _operationsStatus[operationId];
        if (operationStatus == Constants.OPERATION_EXECUTED) {
            revert Errors.OperationAlreadyExecuted(operation);
        } else if (operationStatus == Constants.OPERATION_CANCELLED) {
            revert Errors.OperationAlreadyCancelled(operation);
        } else if (operationStatus == Constants.OPERATION_QUEUED) {
            revert Errors.OperationAlreadyQueued(operation);
        }

        _operationsRelayerQueueAction[operationId] = Action(_msgSender(), uint64(block.timestamp));
        _operationsStatus[operationId] = Constants.OPERATION_QUEUED;
        unchecked {
            ++numberOfOperationsInQueue;
        }

        emit OperationQueued(operation);
    }

    function _challengePeriodOf(bytes32 operationId, bytes1 operationStatus) internal view returns (uint64, uint64) {
        // TODO: What is the challenge period of an already executed/cancelled operation
        if (operationStatus != Constants.OPERATION_QUEUED) return (0, 0);

        Action storage queueAction = _operationsRelayerQueueAction[operationId];
        uint64 startTimestamp = queueAction.timestamp;
        uint64 endTimestamp = startTimestamp + getCurrentChallengePeriodDuration();
        if (_operationsTotalCancelActions[operationId] == 0) {
            return (startTimestamp, endTimestamp);
        }

        if (_operationsGuardianCancelAction[operationId].actor != address(0)) {
            endTimestamp += 432000; // +5days
        }

        if (_operationsSentinelCancelAction[operationId].actor != address(0)) {
            endTimestamp += 432000; // +5days
        }

        return (startTimestamp, endTimestamp);
    }

    function _protocolCancelOperation(Operation calldata operation, Actor actor) internal {
        bytes32 operationId = operationIdOf(operation);

        bytes1 operationStatus = _operationsStatus[operationId];
        if (operationStatus == Constants.OPERATION_EXECUTED) {
            revert Errors.OperationAlreadyExecuted(operation);
        } else if (operationStatus == Constants.OPERATION_CANCELLED) {
            revert Errors.OperationAlreadyCancelled(operation);
        } else if (operationStatus == Constants.OPERATION_NULL) {
            revert Errors.OperationNotQueued(operation);
        }

        (uint64 startTimestamp, uint64 endTimestamp) = _challengePeriodOf(operationId, operationStatus);
        if (uint64(block.timestamp) >= endTimestamp) {
            revert Errors.ChallengePeriodTerminated(startTimestamp, endTimestamp);
        }

        Action memory action = Action(_msgSender(), uint64(block.timestamp));
        if (actor == Actor.Governance) {
            if (_operationsGovernanceCancelAction[operationId].actor != address(0)) {
                revert Errors.GovernanceOperationAlreadyCancelled(operation);
            }

            _operationsGovernanceCancelAction[operationId] = action;
            emit GovernanceOperationCancelled(operation);
        }
        if (actor == Actor.Guardian) {
            if (_operationsGuardianCancelAction[operationId].actor != address(0)) {
                revert Errors.GuardianOperationAlreadyCancelled(operation);
            }

            _operationsGuardianCancelAction[operationId] = action;
            emit GuardianOperationCancelled(operation);
        }
        if (actor == Actor.Sentinel) {
            if (_operationsSentinelCancelAction[operationId].actor != address(0)) {
                revert Errors.SentinelOperationAlreadyCancelled(operation);
            }

            _operationsSentinelCancelAction[operationId] = action;
            emit SentinelOperationCancelled(operation);
        }

        unchecked {
            ++_operationsTotalCancelActions[operationId];
        }
        if (_operationsTotalCancelActions[operationId] == 2) {
            unchecked {
                --numberOfOperationsInQueue;
            }
            _operationsStatus[operationId] = Constants.OPERATION_CANCELLED;
            // TODO: Where should we send the lockedAmountChallengePeriod?
            emit OperationCancelled(operation);
        }
    }

    function _onGovernanceMessage(bytes memory message) internal override {
        bytes memory decodedMessage = abi.decode(message, (bytes));
        (bytes32 messageType, bytes memory data) = abi.decode(decodedMessage, (bytes32, bytes));

        if (messageType == Constants.GOVERNANCE_MESSAGE_SENTINELS) {
            (uint16 epoch, bytes32 sentinelRoot) = abi.decode(data, (uint16, bytes32));
            _epochsSentinelsRoot[epoch] = bytes32(sentinelRoot);
            return;
        }

        // if (messageType == Constants.GOVERNANCE_MESSAGE_GUARDIANS) {
        //     guardiansRoot = bytes32(data);
        //     return;
        // }

        revert Errors.InvalidGovernanceMessage(message);
    }
}

