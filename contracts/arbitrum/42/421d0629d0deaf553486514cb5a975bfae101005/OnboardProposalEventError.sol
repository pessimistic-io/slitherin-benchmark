// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface OnboardProposalEventError {
    event NewProposal(
        string name,
        address token,
        address proposer,
        uint256 maxCapacity,
        uint256 priceRatio
    );

    event ProposalVotingStart(uint256 proposalId, uint256 timestamp);

    event ProposalClosed(uint256 proposalId, uint256 timestamp);

    event ProposalVoted(
        uint256 proposalId,
        address indexed user,
        uint256 voteFor,
        uint256 amount
    );

    event ProposalSettled(uint256 proposalId, uint256 result);

    event ProposalFailed(uint256 proposalId);

    event Claimed(uint256 proposalId, address user, uint256 amount);

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Errors ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    error OnboardProposal__WrongStatus();
    error OnboardProposal__WrongPeriod();
    error OnboardProposal__WrongChoice();
    error OnboardProposal__ChooseBothSides();
    error OnboardProposal__NotEnoughVeDEG();
    error OnboardProposal__NotSettled();
    error OnboardProposal__NotWrongChoice();
    error OnboardProposal__AlreadyClaimed();
    error OnboardProposal__ProposeNotExist();
    error OnboardProposal__AlreadyProposed();
    error OnboardProposal__AlreadyProtected();
    error OnboardProposal__WrongCapacity();
    error OnboardProposal__WrongPremium();
    error OnboardProposal__ZeroAmount();
}

