// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {IGovernanceMessageHandler} from "./IGovernanceMessageHandler.sol";

/**
 * @title IStateManager
 * @author pNetwork
 *
 * @notice
 */
interface IStateManager is IGovernanceMessageHandler {
    enum Actor {
        Governance,
        Guardian,
        Sentinel
    }

    struct Operation {
        bytes32 originBlockHash;
        bytes32 originTransactionHash;
        bytes32 optionsMask;
        uint256 nonce;
        uint256 underlyingAssetDecimals;
        uint256 assetAmount;
        address underlyingAssetTokenAddress;
        bytes4 originNetworkId;
        bytes4 destinationNetworkId;
        bytes4 underlyingAssetNetworkId;
        string destinationAccount;
        string underlyingAssetName;
        string underlyingAssetSymbol;
        bytes userData;
    }

    struct Action {
        address actor;
        uint64 timestamp;
    }

    /**
     * @dev Emitted when an operation is queued.
     *
     * @param operation The queued operation
     */
    event OperationQueued(Operation operation);

    /**
     * @dev Emitted when an operation is executed.
     *
     * @param operation The executed operation
     */
    event OperationExecuted(Operation operation);

    /**
     * @dev Emitted when an operation is cancelled.
     *
     * @param operation The cancelled operation
     */
    event OperationCancelled(Operation operation);

    /**
     * @dev Emitted when the Governance instruct an cancel action on an operation.
     *
     * @param operation The cancelled operation
     */
    event GovernanceOperationCancelled(Operation operation);

    /**
     * @dev Emitted when a Guardian instruct an cancel action on an operation.
     *
     * @param operation The cancelled operation
     */
    event GuardianOperationCancelled(Operation operation);

    /**
     * @dev Emitted when a Sentinel instruct an cancel action on an operation.
     *
     * @param operation The cancelled operation
     */
    event SentinelOperationCancelled(Operation operation);

    /*
     * @notice Calculates the operation challenge period.
     *
     * @param operation
     *
     * @return (uint64, uin64) representing the start and end timestamp of an operation challenge period.
     */
    function challengePeriodOf(Operation calldata operation) external view returns (uint64, uint64);

    /*
     * @notice Returns the sentinels merkle root for a given epoch.
     *
     * @param epoch
     *
     * @return bytes32 representing the sentinels merkle root for a given epoch.
     */
    function getSentinelsRootForEpoch(uint16 epoch) external view returns (bytes32);

    /*
     * @notice Calculates the operation id.
     *
     * @param operation
     *
     * @return (bytes32) the operation id.
     */
    function operationIdOf(Operation memory operation) external pure returns (bytes32);

    /*
     * @notice A Guardian instruct a cancel action. If 2 actors agree on it the operation is cancelled.
     *
     * @param operation
     * @param proof
     *
     */
    function protocolGuardianCancelOperation(Operation calldata operation, bytes calldata proof) external;

    /*
     * @notice The Governance instruct a cancel action. If 2 actors agree on it the operation is cancelled.
     *
     * @param operation
     * @param proof
     *
     */
    function protocolGovernanceCancelOperation(Operation calldata operation, bytes calldata proof) external;

    /*
     * @notice A Sentinel instruct a cancel action. If 2 actors agree on it the operation is cancelled.
     *
     * @param operation
     * @param proof
     *
     */
    function protocolSentinelCancelOperation(Operation calldata operation, bytes calldata proof) external;

    /*
     * @notice Execute an operation that has been queued.
     *
     * @param operation
     *
     */
    function protocolExecuteOperation(Operation calldata operation) external payable;

    /*
     * @notice Queue an operation.
     *
     * @param operation
     *
     */
    function protocolQueueOperation(Operation calldata operation) external payable;
}

