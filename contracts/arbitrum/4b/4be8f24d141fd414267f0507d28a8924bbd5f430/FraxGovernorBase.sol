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
// ========================= FraxGovernorBase =========================
// ====================================================================
// Inherited by FraxGovernor
// veFXS holders can delegate votes to other addresses to vote on their behalf

// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jon Walch: https://github.com/jonwalch

import { Math } from "./Math.sol";
import { GovernorCountingFractional, SafeCast } from "./GovernorCountingFractional.sol";
import { ISafe } from "./ISafe.sol";
import { IVeFxs } from "./IVeFxs.sol";

struct ConstructorParams {
    address veFxs;
    string _name;
    uint256 initialVotingDelay;
    uint256 initialVotingPeriod;
    uint256 initialProposalThreshold;
    uint256 initialQuorum;
    uint256 initialShortCircuitThreshold;
}

abstract contract FraxGovernorBase is GovernorCountingFractional {
    using SafeCast for uint256;

    uint256 public constant QUORUM_DENOMINATOR = 100;

    uint256 public quorumNumerator;
    uint256 public shortCircuitThreshold;

    /// Address of the veFXS contract
    IVeFxs public immutable VE_FXS;

    event QuorumSet(uint256 oldQuorum, uint256 newQuorum);
    event ShortCircuitThresholdSet(uint256 oldShortCircuitThreshold, uint256 newShortCircuitThreshold);

    constructor(
        ConstructorParams memory params
    )
        GovernorCountingFractional(
            params._name,
            params.initialVotingDelay,
            params.initialVotingPeriod,
            params.initialProposalThreshold
        )
    {
        VE_FXS = IVeFxs(params.veFxs);
        _setVotingQuorum(params.initialQuorum);
        _setShortCircuitThreshold(params.initialShortCircuitThreshold);
    }

    function _requireVeFxsProposalThreshold() internal view {
        if (_getVotes(_msgSender(), block.timestamp, "") < proposalThreshold()) revert OnlyVeFxs();
    }

    // only change is removing require statement for token holding, we do that in inhering contracts
    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256) {
        address proposer = _msgSender();
        uint256 currentTimepoint = clock();

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal");
        require(proposals[proposalId].proposer == address(0), "Governor: proposal already exists");

        uint256 snapshot = currentTimepoint + votingDelay();
        uint256 deadline = snapshot + votingPeriod();

        proposals[proposalId] = ProposalCore({
            proposer: proposer,
            voteStart: snapshot.toUint64(),
            voteEnd: deadline.toUint64(),
            executed: false,
            canceled: false,
            __gap_unused0: 0,
            __gap_unused1: 0
        });

        emit ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            deadline,
            description
        );

        return proposalId;
    }

    function _setVotingQuorum(uint256 _votingQuorum) internal {
        uint256 oldQuorum = quorumNumerator;
        quorumNumerator = _votingQuorum;
        emit QuorumSet({ oldQuorum: oldQuorum, newQuorum: _votingQuorum });
    }

    function _setShortCircuitThreshold(uint256 _shortCircuitThreshold) internal {
        uint256 oldThreshold = shortCircuitThreshold;
        shortCircuitThreshold = _shortCircuitThreshold;
        emit ShortCircuitThresholdSet({
            oldShortCircuitThreshold: oldThreshold,
            newShortCircuitThreshold: _shortCircuitThreshold
        });
    }

    function _quorumReached(uint256 proposalId) internal view override returns (bool) {
        (uint256 againstVoteWeight, uint256 forVoteWeight, uint256 abstainVoteWeight) = proposalVotes(proposalId);
        uint256 larger = againstVoteWeight > forVoteWeight ? againstVoteWeight : forVoteWeight;

        return quorum(proposalSnapshot(proposalId)) <= larger + abstainVoteWeight;
    }

    function _shortCircuitFor(uint256 proposalId) internal view returns (bool) {
        (, uint256 forVoteWeight, ) = proposalVotes(proposalId);

        return
            forVoteWeight >
            (VE_FXS.totalSupply(proposalSnapshot(proposalId)) * shortCircuitThreshold) / QUORUM_DENOMINATOR;
    }

    function _shortCircuitAgainst(uint256 proposalId) internal view returns (bool) {
        (uint256 againstVoteWeight, , ) = proposalVotes(proposalId);

        return
            againstVoteWeight >
            (VE_FXS.totalSupply(proposalSnapshot(proposalId)) * shortCircuitThreshold) / QUORUM_DENOMINATOR;
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function COUNTING_MODE() public pure override returns (string memory) {
        return "support=bravo&quorum=against,abstain&quorum=for,abstain&params=fractional";
    }

    function quorum(uint256 timepoint) public view override returns (uint256) {
        return (VE_FXS.totalSupply(timepoint) * quorumNumerator) / QUORUM_DENOMINATOR;
    }

    error OnlyVeFxs();
    error Unauthorized();
}

