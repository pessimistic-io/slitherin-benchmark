// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { VeFxsVotingDelegation } from "./VeFxsVotingDelegation.sol";

interface IFraxGovernorAlpha {
    function $snapshotToTotalVeFxsSupply(uint256) external view returns (uint256);

    function BALLOT_TYPEHASH() external view returns (bytes32);

    function BLOCK_TIME() external view returns (uint256);

    function CLOCK_MODE() external view returns (string memory);

    function COUNTING_MODE() external pure returns (string memory);

    function EXTENDED_BALLOT_TYPEHASH() external view returns (bytes32);

    function VE_FXS() external view returns (address);

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

    function clock() external view returns (uint48);

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

    function getVotes(address account, uint256 timepoint) external view returns (uint256);

    function getVotesWithParams(
        address account,
        uint256 timepoint,
        bytes memory params
    ) external view returns (uint256);

    function hasVoted(uint256 proposalId, address account) external view returns (bool);

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external pure returns (uint256);

    function name() external view returns (string memory);

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

    function proposalProposer(uint256 proposalId) external view returns (address);

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

    function quorumDenominator() external view returns (uint256);

    function quorumNumerator(uint256 timepoint) external view returns (uint256);

    function quorumNumerator() external view returns (uint256);

    function relay(address target, uint256 value, bytes memory data) external payable;

    function setProposalThreshold(uint256 newProposalThreshold) external;

    function setShortCircuitThreshold(uint256 _shortCircuitThreshold) external;

    function setVeFxsVotingDelegation(address _veFxsVotingDelegation) external;

    function setVotingDelay(uint256 newVotingDelay) external;

    function setVotingPeriod(uint256 newVotingPeriod) external;

    function shortCircuitThreshold() external view returns (uint256);

    function state(uint256 proposalId) external view returns (uint8);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function token() external view returns (address);

    function updateQuorumNumerator(uint256 newQuorumNumerator) external;

    function version() external view returns (string memory);

    function voteWeightCast(uint256 proposalId, address account) external view returns (uint128);

    function votingDelay() external view returns (uint256);

    function votingPeriod() external view returns (uint256);
}

