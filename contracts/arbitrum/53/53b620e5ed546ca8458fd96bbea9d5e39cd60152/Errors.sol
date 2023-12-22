// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {IStateManager} from "./IStateManager.sol";

library Errors {
    error OperationAlreadyQueued(IStateManager.Operation operation);
    error OperationAlreadyExecuted(IStateManager.Operation operation);
    error OperationAlreadyCancelled(IStateManager.Operation operation);
    error OperationCancelled(IStateManager.Operation operation);
    error OperationNotQueued(IStateManager.Operation operation);
    error GovernanceOperationAlreadyCancelled(IStateManager.Operation operation);
    error GuardianOperationAlreadyCancelled(IStateManager.Operation operation);
    error SentinelOperationAlreadyCancelled(IStateManager.Operation operation);
    error ChallengePeriodNotTerminated(uint64 startTimestamp, uint64 endTimestamp);
    error ChallengePeriodTerminated(uint64 startTimestamp, uint64 endTimestamp);
    error InvalidUnderlyingAssetName(string underlyingAssetName, string expectedUnderlyingAssetName);
    error InvalidUnderlyingAssetSymbol(string underlyingAssetSymbol, string expectedUnderlyingAssetSymbol);
    error InvalidUnderlyingAssetDecimals(uint256 underlyingAssetDecimals, uint256 expectedUnderlyingAssetDecimals);
    error InvalidAssetParameters(uint256 assetAmount, address assetTokenAddress);
    error SenderIsNotRouter();
    error SenderIsNotStateManager();
    error InvalidUserOperation();
    error NoUserOperation();
    error PTokenNotCreated(address pTokenAddress);
    error InvalidNetwork(bytes4 networkId);
    error NotContract(address addr);
    error LockDown();
    error InvalidGovernanceStateReader(address expectedGovernanceStateReader, address governanceStateReader);
    error InvalidTopic(bytes32 expectedTopic, bytes32 topic);
    error InvalidReceiptsRootMerkleProof();
    error InvalidRootHashMerkleProof();
    error InvalidHeaderBlock();
    error NotRouter(address sender, address router);
    error InvalidAmount(uint256 amount, uint256 expectedAmount);
    error InvalidSourceChainId(uint32 sourceChainId, uint32 expectedSourceChainId);
    error InvalidGovernanceMessageVerifier(
        address governanceMessagerVerifier,
        address expectedGovernanceMessageVerifier
    );
    error InvalidSentinelRegistration(bytes1 kind);
    error InvalidGovernanceMessage(bytes message);
    error InvalidLockedAmountChallengePeriod(
        uint256 lockedAmountChallengePeriod,
        uint256 expectedLockedAmountChallengePeriod
    );
    error CallFailed();
    error QueueFull();
}

