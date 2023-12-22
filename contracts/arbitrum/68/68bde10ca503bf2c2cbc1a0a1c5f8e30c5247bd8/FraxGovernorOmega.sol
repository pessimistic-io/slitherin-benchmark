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

import { SignatureDecoder } from "./SignatureDecoder.sol";
import { FraxGovernorBase, ConstructorParams as FraxGovernorBaseParams } from "./FraxGovernorBase.sol";
import { FraxGovernorAlpha } from "./FraxGovernorAlpha.sol";
import { IVotes } from "./IVotes.sol";
import { ISafe, Enum } from "./ISafe.sol";
import { IFraxGovernorOmega } from "./IFraxGovernorOmega.sol";

struct ConstructorParams {
    address veFxs;
    address payable _fraxGovernorAlpha;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
    uint256 initialProposalThreshold;
    uint256 initialQuorum;
    uint256 initialSafeRequiredSignatures;
    uint256 initialShortCircuitThreshold;
}

contract FraxGovernorOmega is SignatureDecoder, IVotes, FraxGovernorBase {
    uint256 public safeRequiredSignatures;

    FraxGovernorAlpha public immutable FRAX_GOVERNOR_ALPHA;

    //mapping(uint256 proposalId => bytes32 txHash) public vetoProposalIdToTxHash;
    mapping(uint256 => bytes32) public optimisticProposalIdToTxHash;
    //mapping(address safe => mapping(uint256 safeNonce => bytes32 txHash)) public gnosisSafeToNonceToHash;
    mapping(address => mapping(uint256 => bytes32)) public gnosisSafeToNonceToTxHash;

    event TransactionProposed(
        address indexed safe,
        uint256 nonce,
        bytes32 txHash,
        uint256 proposalId,
        address indexed proposer
    );
    event SafeRequiredSignaturesSet(uint256 oldRequiredSignatures, uint256 newRequiredSignatures);

    /**
     * @dev This will construct new contract owners for the _teamSafe
     */
    constructor(
        ConstructorParams memory params
    )
        FraxGovernorBase(
            FraxGovernorBaseParams({
                veFxs: params.veFxs,
                _name: "FraxGovernorOmega",
                initialVotingDelay: params.initialVotingDelay,
                initialVotingPeriod: params.initialVotingPeriod,
                initialProposalThreshold: params.initialProposalThreshold,
                initialQuorum: params.initialQuorum,
                initialShortCircuitThreshold: params.initialShortCircuitThreshold
            })
        )
    {
        FRAX_GOVERNOR_ALPHA = FraxGovernorAlpha(params._fraxGovernorAlpha);
        _setSafeRequiredSignatures(params.initialSafeRequiredSignatures);
    }

    function _requireOnlyGovernorAlpha() internal view {
        if (msg.sender != address(FRAX_GOVERNOR_ALPHA)) revert IFraxGovernorOmega.NotGovernorAlpha();
    }

    function _requireAllowlist(ISafe safe) internal view {
        if (FRAX_GOVERNOR_ALPHA.gnosisSafeAllowlist(address(safe)) != 1) revert Unauthorized();
    }

    // Disallow v == 0 and v == 1 cases of safe.checkNSignatures(). This ensures that the signatures passed in are from
    // EOAs and don't allow the implicit signing from Omega with msg.sender == currentOwner.
    function _requireEoaSignatures(bytes calldata signatures) internal view {
        uint8 v;
        uint256 i;

        for (i = 0; i < safeRequiredSignatures; ++i) {
            (v, , ) = signatureSplit(signatures, i);
            if (v < 2) {
                revert IFraxGovernorOmega.WrongSafeSignatureType();
            }
        }
    }

    function _getVotes(
        address account,
        uint256 timepoint,
        bytes memory /* params */
    ) internal view override returns (uint256) {
        return FRAX_GOVERNOR_ALPHA.getVotes({ account: account, timepoint: timepoint });
    }

    function _optimisticProposalArgs(
        address safe,
        bytes32 txHash
    ) internal pure returns (address[] memory, uint256[] memory, bytes[] memory) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = safe;
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(ISafe.approveHash.selector, txHash);
        return (targets, values, calldatas);
    }

    // Exists solely to avoid stack too deep errors in addTransaction()
    function _safeGetTransactionHash(
        ISafe safe,
        IFraxGovernorOmega.TxHashArgs memory args
    ) internal view returns (bytes32) {
        return
            safe.getTransactionHash({
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

    function _setSafeRequiredSignatures(uint256 newRequiredSignatures) internal {
        uint256 oldSignatures = safeRequiredSignatures;
        safeRequiredSignatures = newRequiredSignatures;
        emit SafeRequiredSignaturesSet({
            oldRequiredSignatures: oldSignatures,
            newRequiredSignatures: newRequiredSignatures
        });
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        _requireVeFxsProposalThreshold();

        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            // Only allow privileged functions to be called through addTransaction flow
            // Disallow allowlisted safes because Omega would be able to call approveHash outside of the
            // rejectTransaction and approveTransaction flow
            if (target == address(this) || FRAX_GOVERNOR_ALPHA.gnosisSafeAllowlist(target) == 1) {
                revert IFraxGovernorOmega.DisallowedTarget(target);
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
        if (optimisticProposalIdToTxHash[hashProposal(targets, values, calldatas, descriptionHash)] != 0) {
            revert IFraxGovernorOmega.CannotCancelVetoTransaction();
        }

        return super.cancel(targets, values, calldatas, descriptionHash);
    }

    function addTransaction(
        address teamSafe,
        IFraxGovernorOmega.TxHashArgs calldata args,
        bytes calldata signatures
    ) external returns (uint256 optimisticProposalId) {
        _requireEoaSignatures(signatures);
        ISafe safe = ISafe(teamSafe);
        // These checks stops EOA Safe owners from pushing txs through that skip the more stringent FraxGovernorAlpha
        // procedures. Swapping owners or changing governance parameters are initiated by using FraxGovernorAlpha.
        if (args.to == address(this) || args.to == address(safe)) {
            revert IFraxGovernorOmega.DisallowedTarget(args.to);
        }
        _requireAllowlist(safe);
        if (gnosisSafeToNonceToTxHash[address(safe)][args._nonce] != 0) revert IFraxGovernorOmega.NonceReserved();
        if (args._nonce < safe.nonce()) revert IFraxGovernorOmega.WrongNonce();

        bytes32 txHash = _safeGetTransactionHash({ safe: safe, args: args });

        safe.checkNSignatures({
            dataHash: txHash,
            data: args.data,
            signatures: signatures,
            requiredSignatures: safeRequiredSignatures
        });

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _optimisticProposalArgs(
            address(safe),
            txHash
        );

        optimisticProposalId = _propose(targets, values, calldatas, "");

        optimisticProposalIdToTxHash[optimisticProposalId] = txHash;
        gnosisSafeToNonceToTxHash[address(safe)][args._nonce] = txHash;

        emit TransactionProposed({
            safe: address(safe),
            nonce: args._nonce,
            txHash: txHash,
            proposalId: optimisticProposalId,
            proposer: msg.sender
        });
    }

    function rejectTransaction(address teamSafe, uint256 nonce) external {
        bytes32 originalTxHash = gnosisSafeToNonceToTxHash[teamSafe][nonce];

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _optimisticProposalArgs(
            teamSafe,
            originalTxHash
        );
        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes("")));

        if (state(proposalId) != ProposalState.Defeated) revert IFraxGovernorOmega.WrongProposalState();

        ISafe safe = ISafe(teamSafe);
        bytes32 rejectTxHash = _safeGetTransactionHash({
            safe: safe,
            args: IFraxGovernorOmega.TxHashArgs({
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
            })
        });

        if (safe.approvedHashes({ signer: address(this), txHash: rejectTxHash }) == 1) {
            revert IFraxGovernorOmega.TransactionAlreadyApproved(rejectTxHash);
        }

        safe.approveHash(rejectTxHash);
    }

    /**
     * @notice Immediately negate a gnosis tx and veto proposal with a 0 eth transfer
     * @notice Cannot be applied to swap owner proposals or governance parameter proposals.
     * @notice An EOA owner will go into the safe UI, use the reject transaction flow, and get 3 EOA owners to sign
     * @param signatures 3 valid signatures from 3/5 EOA owners of the multisig
     */
    function abortTransaction(address teamSafe, bytes calldata signatures) external {
        _requireEoaSignatures(signatures);
        ISafe safe = ISafe(teamSafe);
        _requireAllowlist(safe);

        uint256 nonce = safe.nonce();

        bytes32 rejectTxHash = safe.getTransactionHash({
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
            dataHash: rejectTxHash,
            data: "",
            signatures: signatures,
            requiredSignatures: safeRequiredSignatures
        });

        bytes32 originalTxHash = gnosisSafeToNonceToTxHash[address(safe)][nonce];
        uint256 abortedProposalId;

        // If safe/nonce tuple already had addTransaction() called for it
        if (originalTxHash != 0) {
            (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _optimisticProposalArgs(
                teamSafe,
                originalTxHash
            );

            abortedProposalId = hashProposal(targets, values, calldatas, keccak256(bytes("")));
            ProposalState proposalState = state(abortedProposalId);

            // Cancel voting for proposal
            if (proposalState == ProposalState.Pending || proposalState == ProposalState.Active) {
                proposals[abortedProposalId].canceled = true;
                emit ProposalCanceled(abortedProposalId);
            }
        }

        // Omega approves 0 eth transfer
        safe.approveHash(rejectTxHash);
    }

    function setVotingDelay(uint256 newVotingDelay) public override {
        _requireOnlyGovernorAlpha();
        _setVotingDelay(newVotingDelay);
    }

    function setVotingPeriod(uint256 newVotingPeriod) public override {
        _requireOnlyGovernorAlpha();
        _setVotingPeriod(newVotingPeriod);
    }

    function setProposalThreshold(uint256 newProposalThreshold) public override {
        _requireOnlyGovernorAlpha();
        _setProposalThreshold(newProposalThreshold);
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
        _setSafeRequiredSignatures(newRequiredSignatures);
    }

    function getVotes(address account) external view returns (uint256) {
        return _getVotes(account, block.timestamp, "");
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        return FRAX_GOVERNOR_ALPHA.getPastVotes(account, timepoint);
    }

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
        return FRAX_GOVERNOR_ALPHA.getPastTotalSupply(timepoint);
    }

    function delegates(address account) external view returns (address) {
        return FRAX_GOVERNOR_ALPHA.delegates(account);
    }

    //TODO: maybe make this callable from alpha (only by omega) but that makes them too tightly coupled
    function delegate(address /* delegatee */) external pure {
        revert IFraxGovernorOmega.DelegateWithAlpha();
    }

    //TODO: maybe make this callable from alpha (only by omega) but that makes them too tightly coupled
    function delegateBySig(
        address, // delegatee
        uint256, // nonce
        uint256, // expiry
        uint8, // v
        bytes32, // r
        bytes32 // s
    ) public virtual override {
        revert IFraxGovernorOmega.DelegateWithAlpha();
    }

    function _optimisticVoteDefeated(uint256 proposalId) internal view returns (bool) {
        (uint256 againstVoteWeight, uint256 forVoteWeight, ) = proposalVotes(proposalId);
        if (againstVoteWeight == 0 && forVoteWeight == 0) {
            return false;
        } else {
            return forVoteWeight <= againstVoteWeight;
        }
    }

    function state(uint256 proposalId) public view override returns (ProposalState) {
        ProposalCore storage proposal = proposals[proposalId];

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert("Governor: unknown proposal id");
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return ProposalState.Pending;
        }

        // Allow early execution when overwhelming majority
        bool quorumReached = _quorumReached(proposalId);
        if (quorumReached) {
            if (_shortCircuitFor(proposalId)) {
                return ProposalState.Succeeded;
            } else if (_shortCircuitAgainst(proposalId)) {
                return ProposalState.Defeated;
            }
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        }

        // Optimistic proposal with addTransaction()
        if (optimisticProposalIdToTxHash[proposalId] != 0) {
            if (quorumReached && _optimisticVoteDefeated(proposalId)) {
                return ProposalState.Defeated;
            } else {
                return ProposalState.Succeeded;
            }

            // Regular proposal with propose()
        } else {
            if (quorumReached && _voteSucceeded(proposalId)) {
                return ProposalState.Succeeded;
            } else {
                return ProposalState.Defeated;
            }
        }
    }
}

