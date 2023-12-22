// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// =========================== FraxGovernor ===========================
// ====================================================================
// # FraxGovernor
// This contract controls the FraxGovernanceOwner

// # Overview

// # Requirements

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jon Walch: https://github.com/jonwalch
// Jamie Turley: https://github.com/jyturley

import {FraxGovernorBase, ConstructorParams as FraxGovernorBaseParams} from "./FraxGovernorBase.sol";
import {FraxGovernorAlpha} from "./FraxGovernorAlpha.sol";
import "./ISafe.sol";
import "./IFraxGovernor.sol";

struct ConstructorParams {
    address veFxs;
    address payable _fraxGovernorAlpha;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
    uint256 initialQuorum;
    uint256 initialSafeRequiredSignatures;
    uint256 initialShortCircuitThreshold;
}

/**
 * @notice Voting contract for veFXS holders
 */
contract FraxGovernorOmega is FraxGovernorBase, IFraxGovernor {
    uint256 public safeRequiredSignatures;

    FraxGovernorAlpha public immutable FRAX_GOVERNOR_ALPHA;

    //mapping(bytes32 txHash => uint256 proposalId) public hashToVetoProposalId;
    mapping(bytes32 => uint256) public hashToVetoProposalId;
    //mapping(uint256 proposalId => bytes32 txHash) public vetoProposalIdToTxHash;
    mapping(uint256 => bytes32) public vetoProposalIdToTxHash;
    //mapping(address safe => mapping(uint256 safeNonce => bytes32 txHash)) public gnosisSafeToNonceToHash;
    mapping(address => mapping(uint256 => bytes32)) public gnosisSafeToNonceToHash;

    error OnlyVeFxs();
    error CannotCancelVetoTransaction();

    event SafeRequiredSignaturesSet(uint256 oldRequiredSignatures, uint256 newRequiredSignatures);

    /**
     * @dev This will construct new contract owners for the _teamSafe
     */
    constructor(ConstructorParams memory params)
        FraxGovernorBase(
            FraxGovernorBaseParams({
                veFxs: params.veFxs,
                _name: "FraxGovernorOmega",
                initialVotingDelay: params.initialVotingDelay,
                initialVotingPeriod: params.initialVotingPeriod,
                initialQuorum: params.initialQuorum,
                initialShortCircuitThreshold: params.initialShortCircuitThreshold
            })
        )
    {
        FRAX_GOVERNOR_ALPHA = FraxGovernorAlpha(params._fraxGovernorAlpha);
        safeRequiredSignatures = params.initialSafeRequiredSignatures;
    }

    function _requireOnlyGovernorAlpha() internal view {
        if (msg.sender != address(FRAX_GOVERNOR_ALPHA)) revert NotGovernorAlpha();
    }

    function _requireAllowlist(ISafe safe) internal view {
        if (FRAX_GOVERNOR_ALPHA.gnosisSafeAllowlist(address(safe)) != 1) revert Unauthorized();
    }

    /**
     * @notice Ensure functions can only be called by veFXS holders
     */
    function _requireVeFxsHolder(address account) internal view {
        if (VE_FXS.balanceOf(account) < FRAX_GOVERNOR_ALPHA.minimumVeFxsForGovernance()) revert OnlyVeFxs();
    }

    // Exists solely to avoid stack too deep errors in addTransaction()
    function _safeGetTransactionHash(ISafe safe, TxHashArgs calldata args) internal view returns (bytes32) {
        return safe.getTransactionHash({
            to: args.to,
            value: args.value,
            data: args.data,
            operation: args.operation,
            safeTxGas: args.safeTxGas,
            baseGas: args.baseGas,
            gasPrice: args.gasPrice,
            gasToken: args.gasToken,
            refundReceiver: args.refundReceiver,
            _nonce: args._nonce
        });
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        _requireVeFxsHolder(msg.sender);

        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            // Only allow privileged functions to be called through addTransaction flow
            // Disallow allowlisted safes because Omega would be able to call approveHash outside of the
            // rejectTransaction and approveTransaction flow
            if (target == address(this) || FRAX_GOVERNOR_ALPHA.gnosisSafeAllowlist(target) == 1) {
                revert DisallowedTarget(target);
            }
        }

        return _propose(targets, values, calldatas, description);
    }

    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public override returns (uint256) {
        if (vetoProposalIdToTxHash[hashProposal(targets, values, calldatas, descriptionHash)] != 0) {
            revert CannotCancelVetoTransaction();
        }

        return super.cancel(targets, values, calldatas, descriptionHash);
    }

    function _vetoProposalArgs(address safe, uint256 nonce)
        internal
        view
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(this);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(this.rejectTransaction.selector, address(safe), nonce);
        return (targets, values, calldatas);
    }

    /**
     * @notice Add new transaction to provide a chance for veFXS to veto
     * @notice This may or may not eventually get executed
     * @param args TxHashArgs passed to GnosisSafe.getTransactionHash()
     * @param signatures 3 valid signatures from 3/5 EOA owners of the multisig
     * @return vetoProposalId The proposalId for the accompanying veto proposal
     */
    function addTransaction(address teamSafe, TxHashArgs calldata args, bytes calldata signatures)
        external
        returns (uint256 vetoProposalId)
    {
        ISafe safe = ISafe(teamSafe);
        // These checks stops EOA Safe owners from pushing txs through that skip the more stringent FraxGovernorAlpha
        // procedures. Swapping owners or changing governance parameters are initiated by using FraxGovernorAlpha.
        if (args.to == address(this) || args.to == address(safe)) {
            revert DisallowedTarget(args.to);
        }
        _requireAllowlist(safe);
        if (gnosisSafeToNonceToHash[address(safe)][args._nonce] != 0) revert NonceReserved();
        if (args._nonce < safe.nonce()) revert WrongNonce();

        bytes32 txHash = _safeGetTransactionHash({safe: safe, args: args});

        safe.checkNSignatures({
            dataHash: txHash,
            data: args.data,
            signatures: signatures,
            requiredSignatures: safeRequiredSignatures
        });

        // This is a default veto transaction. Every pro-proposal will have one.
        // It may or may not actually get used.
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _vetoProposalArgs(address(safe), args._nonce);

        vetoProposalId = _propose(targets, values, calldatas, "");

        hashToVetoProposalId[txHash] = vetoProposalId;
        vetoProposalIdToTxHash[vetoProposalId] = txHash;
        gnosisSafeToNonceToHash[address(safe)][args._nonce] = txHash;

        emit TransactionProposed({proposalId: vetoProposalId, proposer: msg.sender, txHash: txHash});
    }

    function rejectTransaction(address teamSafe, uint256 nonce) external onlyGovernance {
        ISafe safe = ISafe(teamSafe);
        bytes32 txHash = safe.getTransactionHash({
            to: address(safe),
            value: 0,
            data: "",
            operation: Enum.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(address(0)),
            _nonce: nonce
        });
        safe.approveHash(txHash);
        emit TransactionApproved({safe: address(safe), approvedTxHash: txHash});
    }

    function approveTransaction(address teamSafe, uint256 nonce) external {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _vetoProposalArgs(teamSafe, nonce);

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes("")));

        if (state(proposalId) != ProposalState.Defeated) revert WrongProposalState();

        bytes32 hashToApprove = vetoProposalIdToTxHash[proposalId];
        ISafe safe = ISafe(teamSafe);

        if (safe.approvedHashes({signer: address(this), txHash: hashToApprove}) == 1) {
            revert TransactionAlreadyApproved(hashToApprove);
        }

        safe.approveHash(hashToApprove);
        emit TransactionApproved({safe: address(safe), approvedTxHash: hashToApprove});
    }

    /**
     * @notice Immediately negate a gnosis tx and veto proposal with a 0 eth transfer
     * @notice Cannot be applied to swap owner proposals or governance parameter proposals.
     * @notice An EOA owner will go into the safe UI, use the reject transaction flow, and get 3 EOA owners to sign
     * @param signatures 3 valid signatures from 3/5 EOA owners of the multisig
     */
    function abortTransaction(address teamSafe, bytes calldata signatures) external {
        ISafe safe = ISafe(teamSafe);
        _requireAllowlist(safe);

        uint256 nonce = safe.nonce();

        bytes32 txHash = safe.getTransactionHash({
            to: address(safe),
            value: 0,
            data: "",
            operation: Enum.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(address(0)),
            _nonce: nonce
        });

        // Check validity of provided 3 signatures for generated txHash
        safe.checkNSignatures({
            dataHash: txHash,
            data: "",
            signatures: signatures,
            requiredSignatures: safeRequiredSignatures
        });
        // Omega approves 0 eth transfer
        safe.approveHash(txHash);
        emit TransactionApproved({safe: address(safe), approvedTxHash: txHash});

        bytes32 abortedTxHash = gnosisSafeToNonceToHash[address(safe)][nonce];
        uint256 abortedProposalId = hashToVetoProposalId[abortedTxHash];

        // If nonce already had addTransaction() called for it
        if (abortedTxHash != 0 && abortedProposalId != 0) {
            ProposalState proposalState = state(abortedProposalId);

            if (proposalState == ProposalState.Pending || proposalState == ProposalState.Active) {
                proposals[abortedProposalId].canceled = true;
                emit ProposalCanceled(abortedProposalId);
            }
            emit TransactionAborted({proposalId: abortedProposalId, rejectedHash: abortedTxHash});
        }
    }

    function setVotingDelay(uint256 newVotingDelay) public override {
        _requireOnlyGovernorAlpha();
        _setVotingDelay(newVotingDelay);
    }

    function setVotingPeriod(uint256 newVotingPeriod) public override {
        _requireOnlyGovernorAlpha();
        _setVotingPeriod(newVotingPeriod);
    }

    function setVotingQuorum(uint256 _votingQuorum) external {
        _requireOnlyGovernorAlpha();
        _setVotingQuorum(_votingQuorum);
    }

    function setShortCircuitThreshold(uint256 _shortCircuitThreshold) external {
        _requireOnlyGovernorAlpha();
        _setShortCircuitThreshold(_shortCircuitThreshold);
    }

    function setSafeRequiredSignatures(uint256 newRequiredSignatures) external {
        _requireOnlyGovernorAlpha();
        uint256 oldSignatures = safeRequiredSignatures;
        safeRequiredSignatures = newRequiredSignatures;
        emit SafeRequiredSignaturesSet({
            oldRequiredSignatures: oldSignatures,
            newRequiredSignatures: newRequiredSignatures
        });
    }

    function _getVotes(address account, uint256 timepoint, bytes memory /* params */ )
        internal
        view
        override
        returns (uint256)
    {
        return FRAX_GOVERNOR_ALPHA.getVotes({account: account, timepoint: timepoint});
    }
}

