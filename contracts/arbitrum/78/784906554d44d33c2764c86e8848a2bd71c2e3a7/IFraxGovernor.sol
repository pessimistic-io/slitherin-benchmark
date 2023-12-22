// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Enum.sol";

interface IFraxGovernor {
    enum ProposalType {
        Veto,
        Governance
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

    event TransactionProposed(uint256 proposalId, address indexed proposer, bytes32 txHash);
    event TransactionApproved(address indexed safe, bytes32 approvedTxHash);
    event TransactionAborted(uint256 proposalId, bytes32 rejectedHash);

    event SafeRegistered(address safe);
    event SafeUnregistered(address safe);

    error TransactionAlreadyApproved(bytes32 txHash);
    error NotGovernorAlpha();
    error WrongNonce();
    error NonceReserved();
    error WrongProposalState();
    error DisallowedTarget(address target);
}

