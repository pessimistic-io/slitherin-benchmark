// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Enum.sol";

interface IFraxGovernor {
    enum ApprovalType {
        RejectTransaction,
        ApproveTransaction,
        AbortTransaction
    }

    struct TxHashArgs {
        address to;
        uint256 value;
        bytes data;
        Enum.Operation operation;
        uint256 safeTxGas;
        uint256 baseGas;
        uint256 gasPrice;
        address gasToken;
        address refundReceiver;
        uint256 _nonce;
    }

    event TransactionProposed(
        address indexed safe, uint256 nonce, bytes32 txHash, uint256 proposalId, address indexed proposer
    );
    event TransactionApproved(
        address indexed safe, uint256 nonce, bytes32 approvedTxHash, uint256 proposalId, ApprovalType approvalType
    );

    event SafeRegistered(address safe);
    event SafeUnregistered(address safe);

    error TransactionAlreadyApproved(bytes32 txHash);
    error NotGovernorAlpha();
    error WrongNonce();
    error NonceReserved();
    error WrongProposalState();
    error DisallowedTarget(address target);
}

