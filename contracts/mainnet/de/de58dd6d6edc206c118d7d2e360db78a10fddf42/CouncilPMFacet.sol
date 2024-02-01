/*
 * This file is part of the Qomet Technologies contracts (https://github.com/qomet-tech/contracts).
 * Copyright (c) 2022 Qomet Technologies (https://qomet.tech)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
// SPDX-License-Identifier: GNU General Public License v3.0

pragma solidity 0.8.1;

import "./IDiamondFacet.sol";
import "./ReentrancyLockLib.sol";
import "./CouncilInternal.sol";

/// @author Kam Amini <kam@arteq.io>
///
/// @notice Use at your own risk
contract CouncilPMFacet is IDiamondFacet {

    modifier reentrancyProtected {
        ReentrancyLockLib._engageLock(HasherLib._hashStr("GLOBAL"));
        _;
        ReentrancyLockLib._releaseLock(HasherLib._hashStr("GLOBAL"));
    }

    function getFacetName()
      external pure override returns (string memory) {
        return "council-pm";
    }

    // CAUTION: Don't forget to update the version when adding new functionality
    function getFacetVersion()
      external pure override returns (string memory) {
        return "1.0.3";
    }

    function getFacetPI()
      external pure override returns (string[] memory) {
        string[] memory pi = new string[](15);
        pi[ 0] = "getNrOfProposals()";
        pi[ 1] = "getProposalInfo(uint256)";
        pi[ 2] = "getAdminProposalStats(uint256)";
        pi[ 3] = "getProposalStats(uint256)";
        pi[ 4] = "getPendingProposals()";
        pi[ 5] = "getAccountProposalStats(uint256,address)";
        pi[ 6] = "createProposal(bool,string,uint256,uint256,string[],uint256,int256,int256,address,address)";
        pi[ 7] = "updateProposal(uint256,string,uint256,uint256,string[],uint256)";
        pi[ 8] = "updateHolderEligibilityThreshold(uint256,uint256)";
        pi[ 9] = "updatePassThreshold(uint256,uint256)";
        pi[10] = "approveProposal(uint256)";
        pi[11] = "withdrawProposalApproval(uint256)";
        pi[12] = "rejectProposal(uint256)";
        pi[13] = "withdrawProposalRejection(uint256)";
        pi[14] = "finalizeProposal(uint256)";
        return pi;
    }

    function getFacetProtectedPI()
      external pure override returns (string[] memory) {
        string[] memory pi = new string[](0);
        return pi;
    }

    function supportsInterface(bytes4 interfaceId)
      external pure override returns (bool) {
        return interfaceId == type(IDiamondFacet).interfaceId;
    }

    function getNrOfProposals() external view returns (uint256) {
        return CouncilInternal._getNrOfProposals();
    }

    function getProposalInfo(
        uint256 proposalId
    ) external view returns (
        string memory, /* proposalURI */
        uint256, /* startTs */
        uint256, /* expireTs */
        string[] memory, /* tags */
        uint256, /* referenceProposalId */
        bool, /* true if an admin proposal */
        bool, /* true if executed */
        bool, /* true if finalized */
        uint256, /* finalizedTs */
        uint256, /* holderEligibilityThreshold */
        uint256  /* passThreshold */
    ) {
        return CouncilInternal._getProposalInfo(proposalId);
    }

    function getAdminProposalStats(
        uint256 adminProposalId
    ) external view returns(
        // number of admins
        uint256,
        // list of admins approving the proposal
        address[] memory,
        // true if the proposal is passed
        bool
    ) {
        return CouncilInternal._getAdminProposalStats(adminProposalId);
    }

    function getProposalStats(
        uint256 proposalId
    ) external view returns(
        // list of accounts approved the proposal
        address[] memory,
        // list of the used balances one-to-one mapped to the approvers list
        uint256[] memory,
        // sum of the balances of approving accounts (balance of the grant tokens)
        uint256,
        // list of accounts rejected the proposal
        address[] memory,
        // list of the used balances one-to-one mapped to the rejectors list
        uint256[] memory,
        // sum of the balances of rejecting accounts (balance of the grant tokens)
        uint256,
        // true if the proposal is passed (or "passed so far" for non-expired
        // and non-finalized proposals)
        bool
    ) {
        return CouncilInternal._getProposalStats(proposalId);
    }

    function getPendingProposals() external view returns (uint256[] memory) {
        return CouncilInternal._getPendingProposals();
    }

    function getAccountProposalStats(
        uint256 proposalId,
        address account
    ) external view returns (
        // true if approved
        bool,
        // true if rejected
        bool,
        // used balance to approve or reject
        uint256
    ) {
        return CouncilInternal._getAccountProposalStats(proposalId, account);
    }

    function createProposal(
        bool admin,
        string memory proposalURI,
        uint256 startTs,
        uint256 expireTs,
        string[] memory tags,
        uint256 referenceProposalId,
        int256 holderEligibilityThreshold,
        int256 passThreshold,
        address payErc20,
        address payer
    ) external reentrancyProtected payable {
        CouncilInternal._createProposal(
            admin, proposalURI, startTs, expireTs, tags,
                referenceProposalId, holderEligibilityThreshold,
                    passThreshold, payErc20, payer);
    }

    function updateProposal(
        uint256 proposalId,
        string memory proposalURI,
        uint256 startTs,
        uint256 expireTs,
        string[] memory tags,
        uint256 referenceProposalId
    ) external {
        CouncilInternal._updateProposal(
            proposalId, proposalURI, startTs, expireTs, tags, referenceProposalId);
    }

    function updateHolderEligibilityThreshold(
        uint256 proposalId,
        uint256 newValue
    ) external {
        CouncilInternal._updateHolderEligibilityThreshold(proposalId, newValue);
    }

    function updatePassThreshold(
        uint256 proposalId,
        uint256 newValue
    ) external {
        CouncilInternal._updatePassThreshold(proposalId, newValue);
    }

    function approveProposal(
        uint256 proposalId
    ) external {
        CouncilInternal._approveProposal(proposalId);
    }

    function withdrawProposalApproval(
        uint256 proposalId
    ) external {
        CouncilInternal._withdrawProposalApproval(proposalId);
    }

    function rejectProposal(
        uint256 proposalId
    ) external {
        CouncilInternal._rejectProposal(proposalId);
    }

    function withdrawProposalRejection(
        uint256 proposalId
    ) external {
        CouncilInternal._withdrawProposalRejection(proposalId);
    }

    function finalizeProposal(
        uint256 proposalId
    ) external {
        CouncilInternal._finalizeProposal(proposalId);
    }
}

