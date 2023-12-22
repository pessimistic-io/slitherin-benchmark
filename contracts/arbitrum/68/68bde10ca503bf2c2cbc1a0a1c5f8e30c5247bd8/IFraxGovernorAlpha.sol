// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { FraxVotingDelegation } from "./FraxVotingDelegation.sol";

interface IFraxGovernorAlpha {
    function BALLOT_TYPEHASH() external view returns (bytes32);

    function CLOCK_MODE() external pure returns (string memory);

    function COUNTING_MODE() external pure returns (string memory);

    function DELEGATION_TYPEHASH() external pure returns (bytes32);

    function EXTENDED_BALLOT_TYPEHASH() external view returns (bytes32);

    function QUORUM_DENOMINATOR() external view returns (uint256);

    function VE_FXS() external view returns (address);

    function VOTE_WEIGHT_MULTIPLIER() external view returns (uint256);

    function WEEK() external view returns (uint256);

    function _VE_FXS() external view returns (address);

    function addSafesToAllowlist(address[] memory safes) external;

//    function calculateExpirations(
//        address account
//    ) external view returns (FraxVotingDelegation.DelegateCheckpoint memory);

    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256);

    function castVote(uint256 proposalId, uint8 support) external returns (uint256);

    function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external returns (uint256);

    function castVoteWithReason(uint256 proposalId, uint8 support, string memory reason) external returns (uint256);

    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) external returns (uint256);

    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256);

    function checkpoints(
        address,
        uint256
    ) external view returns (uint128 normalizedBias, uint128 totalFxs, uint128 normalizedSlope, uint128 timestamp);

    function clock() external view returns (uint48);

    function delegate(address delegatee) external;

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;

    function delegates(address account) external view returns (address);

    function delegations(
        address
    )
        external
        view
        returns (uint256 bias, uint128 fxs, uint128 slope, address delegate, uint48 timestamp, uint48 expiry);

    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable returns (uint256);

    function expirations(address, uint256) external view returns (uint256 bias, uint128 fxs, uint128 slope);

    function getCheckpoint(
        address account,
        uint32 pos
    ) external view returns (FraxVotingDelegation.DelegateCheckpoint memory);

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);

    function getVotes(address account) external view returns (uint256);

    function getVotes(address account, uint256 timepoint) external view returns (uint256);

    function getVotesWithParams(
        address account,
        uint256 timepoint,
        bytes memory params
    ) external view returns (uint256);

    function gnosisSafeAllowlist(address) external view returns (uint256);

    function hasVoted(uint256 proposalId, address account) external view returns (bool);

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external pure returns (uint256);

    function lastExpirations(address) external view returns (uint256);

    function name() external view returns (string memory);

    function nonces(address) external view returns (uint256);

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external returns (bytes4);

    function onERC1155Received(address, address, uint256, uint256, bytes memory) external returns (bytes4);

    function onERC721Received(address, address, uint256, bytes memory) external returns (bytes4);

    function proposalDeadline(uint256 proposalId) external view returns (uint256);

    function proposalSnapshot(uint256 proposalId) external view returns (uint256);

    function proposalThreshold() external view returns (uint256);

    function proposalVotes(
        uint256 proposalId
    ) external view returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes);

    function proposals(
        uint256
    )
        external
        view
        returns (
            uint64 voteStart,
            address proposer,
            bytes4 __gap_unused0,
            uint64 voteEnd,
            bytes24 __gap_unused1,
            bool executed,
            bool canceled
        );

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);

    function quorum(uint256 timepoint) external view returns (uint256);

    function quorumNumerator() external view returns (uint256);

    function relay(address target, uint256 value, bytes memory data) external payable;

    function removeSafesFromAllowlist(address[] memory safes) external;

    function setProposalThreshold(uint256 newProposalThreshold) external;

    function setShortCircuitThreshold(uint256 _shortCircuitThreshold) external;

    function setVotingDelay(uint256 newVotingDelay) external;

    function setVotingPeriod(uint256 newVotingPeriod) external;

    function setVotingQuorum(uint256 _votingQuorum) external;

    function shortCircuitThreshold() external view returns (uint256);

    function state(uint256 proposalId) external view returns (uint8);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function version() external view returns (string memory);

    function voteWeightCast(uint256 proposalId, address account) external view returns (uint128);

    function votingDelay() external view returns (uint256);

    function votingPeriod() external view returns (uint256);

    function writeNewCheckpointForExpirations(address account) external;
}

