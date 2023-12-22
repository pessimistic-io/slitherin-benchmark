// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IStargateRouter } from "./IStargateRouter.sol";
import { VaultRiskProfile } from "./IVaultRiskProfile.sol";

enum GasFunctionType {
    standardNoReturnMessage,
    createChildRequiresReturnMessage,
    getVaultValueRequiresReturnMessage,
    withdrawRequiresReturnMessage,
    sgReceiveRequiresReturnMessage,
    sendBridgeApprovalNoReturnMessage,
    childCreatedNoReturnMessage
}

interface ITransport {
    struct SGReceivePayload {
        address dstVault;
        address srcVault;
        uint16 parentChainId;
        address parentVault;
    }

    struct SGBridgedAssetReceivedAcknoledgementRequest {
        uint16 parentChainId;
        address parentVault;
        uint16 receivingChainId;
    }

    struct ChildVault {
        uint16 chainId;
        address vault;
    }

    struct VaultChildCreationRequest {
        address parentVault;
        uint16 parentChainId;
        uint16 newChainId;
        address manager;
        VaultRiskProfile riskProfile;
        ChildVault[] children;
    }

    struct ChildCreatedRequest {
        address parentVault;
        uint16 parentChainId;
        ChildVault newChild;
    }

    struct AddVaultSiblingRequest {
        ChildVault child;
        ChildVault newSibling;
    }

    struct BridgeApprovalRequest {
        uint16 approvedChainId;
        address approvedVault;
    }

    struct BridgeApprovalCancellationRequest {
        uint16 parentChainId;
        address parentVault;
        address requester;
    }

    struct ValueUpdateRequest {
        uint16 parentChainId;
        address parentVault;
        ChildVault child;
    }

    struct ValueUpdatedRequest {
        uint16 parentChainId;
        address parentVault;
        ChildVault child;
        uint time;
        uint minValue;
        uint maxValue;
        bool hasHardDepreactedAsset;
    }

    struct WithdrawRequest {
        uint16 parentChainId;
        address parentVault;
        ChildVault child;
        uint tokenId;
        address withdrawer;
        uint portion;
    }

    struct WithdrawComplete {
        uint16 parentChainId;
        address parentVault;
    }

    struct ChangeManagerRequest {
        ChildVault child;
        address newManager;
    }

    event VaultChildCreated(address target);
    event VaultParentCreated(address target);

    receive() external payable;

    function addSibling(AddVaultSiblingRequest memory request) external;

    function bridgeApproval(BridgeApprovalRequest memory request) external;

    function bridgeApprovalCancellation(
        BridgeApprovalCancellationRequest memory request
    ) external;

    function bridgeAsset(
        uint16 dstChainId,
        address dstVault,
        uint16 parentChainId,
        address parentVault,
        address bridgeToken,
        uint256 amount,
        uint256 minAmountOut
    ) external payable;

    function childCreated(ChildCreatedRequest memory request) external;

    function createVaultChild(
        VaultChildCreationRequest memory request
    ) external;

    function createParentVault(
        string memory name,
        string memory symbol,
        address manager,
        uint streamingFee,
        uint performanceFee,
        VaultRiskProfile riskProfile
    ) external payable returns (address deployment);

    function sendChangeManagerRequest(
        ChangeManagerRequest memory request
    ) external payable;

    function sendAddSiblingRequest(
        AddVaultSiblingRequest memory request
    ) external;

    function sendBridgeApproval(
        BridgeApprovalRequest memory request
    ) external payable;

    function sendBridgeApprovalCancellation(
        BridgeApprovalCancellationRequest memory request
    ) external payable;

    function sendVaultChildCreationRequest(
        VaultChildCreationRequest memory request
    ) external payable;

    function sendWithdrawRequest(
        WithdrawRequest memory request
    ) external payable;

    function sendValueUpdateRequest(
        ValueUpdateRequest memory request
    ) external payable;

    function updateVaultValue(ValueUpdatedRequest memory request) external;

    function getLzFee(
        GasFunctionType gasFunctionType,
        uint16 dstChainId
    ) external returns (uint256 sendFee, bytes memory adapterParams);

    // onlyThis
    function changeManager(ChangeManagerRequest memory request) external;

    function withdraw(WithdrawRequest memory request) external;

    function withdrawComplete(WithdrawComplete memory request) external;

    function getVaultValue(ValueUpdateRequest memory request) external;

    function sgBridgedAssetReceived(
        SGBridgedAssetReceivedAcknoledgementRequest memory request
    ) external;
}

