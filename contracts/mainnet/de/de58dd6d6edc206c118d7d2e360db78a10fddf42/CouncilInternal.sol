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

import "./IERC20.sol";
import "./AddressSet.sol";
import "./HasherLib.sol";
import "./FiatHandlerLib.sol";
import "./BoardLib.sol";
import "./Constants.sol";
import "./CouncilStorage.sol";

/// @author Kam Amini <kam@arteq.io>
///
/// @notice Use at your own risk
library CouncilInternal {

    event NewProposal(uint256 indexed proposalId);
    event ProposalUpdate(uint256 indexed proposalId);
    event ProposalFinalized(uint256 indexed proposalId);
    event ProposalExecuted(uint256 indexed proposalId);

    modifier mustBeInitialized() {
        require(__s().initialized, "CI:NI");
        _;
    }

    function _initialize(
        uint256 registereeId,
        address grantToken,
        address feeCollectionAccount,
        address icoCollectionAccount,
        uint256 proposalCreationFeeMicroUSD,
        uint256 adminProposalCreationFeeMicroUSD,
        uint256 icoTokenPriceMicroUSD,
        uint256 icoFeeMicroUSD
    ) internal {
        require(!__s().initialized, "CI:AI");
        require(grantToken != address(0), "CI:ZSTA");
        require(feeCollectionAccount != address(0), "CI:ZFCA");
        require(registereeId > 0, "CI:INVREGID");
        __s().registrar = msg.sender;
        __s().registereeId = registereeId;
        __s().grantToken = grantToken;
        __s().feeCollectionAccount = feeCollectionAccount;
        __s().icoCollectionAccount = icoCollectionAccount;
        __s().defaultHolderEligibilityThreshold = 0;
        __s().defaultProposalPassThreshold = 50; // more than 50% approval is needed
        __s().proposalCreationFeeMicroUSD = proposalCreationFeeMicroUSD;
        __s().adminProposalCreationFeeMicroUSD = adminProposalCreationFeeMicroUSD;
        if (icoTokenPriceMicroUSD > 0) {
            __s().icoPhase = true;
            __s().icoTokenPriceMicroUSD = icoTokenPriceMicroUSD;
        }
        __s().icoFeeMicroUSD = icoFeeMicroUSD;
        BoardLib._makeFinalizer(grantToken);
        // exclude council's balance from vote counting
        __s().possibleVotingExcluded.push(address(this));
        __s().votingExcludedMap[address(this)] = true;
        __s().initialized = true;
    }

    function _getCouncilSettings() internal view returns (
        address, // registrar
        uint256, // registereeId
        address, // grantToken
        uint256, // defaultHolderEligibilityThreshold
        uint256, // defaultProposalPassThreshold
        address, // feeCollectionAccount
        address, // icoCollectionAccount
        uint256, // proposalCreationFeeMicroUSD
        uint256, // adminProposalCreationFeeMicroUSD
        bool,    // icoPhase
        uint256, // icoTokenPriceMicroUSD,
        uint256  // icoFeeMicroUSD
    ) {
        return (
            __s().registrar,
            __s().registereeId,
            __s().grantToken,
            __s().defaultHolderEligibilityThreshold,
            __s().defaultProposalPassThreshold,
            __s().feeCollectionAccount,
            __s().icoCollectionAccount,
            __s().proposalCreationFeeMicroUSD,
            __s().adminProposalCreationFeeMicroUSD,
            __s().icoPhase,
            __s().icoTokenPriceMicroUSD,
            __s().icoFeeMicroUSD
        );
    }

    function _setCouncilSettings(
        address feeCollectionAccount,
        address icoCollectionAccount,
        uint256 proposalCreationFeeMicroUSD,
        uint256 adminProposalCreationFeeMicroUSD,
        bool icoPhase,
        uint256 icoTokenPriceMicroUSD,
        uint256 icoFeeMicroUSD
    ) internal mustBeInitialized {
        require(feeCollectionAccount != address(0), "CI:ZWFA");
        __s().feeCollectionAccount = feeCollectionAccount;
        __s().icoCollectionAccount = icoCollectionAccount;
        __s().proposalCreationFeeMicroUSD = proposalCreationFeeMicroUSD;
        __s().adminProposalCreationFeeMicroUSD = adminProposalCreationFeeMicroUSD;
        __s().icoPhase = icoPhase;
        __s().icoTokenPriceMicroUSD = icoTokenPriceMicroUSD;
        __s().icoFeeMicroUSD = icoFeeMicroUSD;
    }

    function _setDefaultHolderEligibilityThreshold(
        uint256 adminProposalId,
        uint256 newValue
    ) internal mustBeInitialized {
        require(newValue >= 0 && newValue <= 100, "CI:INVHET");
        __s().defaultHolderEligibilityThreshold = newValue;
        _executeAdminProposal(address(this), msg.sender, adminProposalId);
    }

    function _setDefaultProposalPassThreshold(
        uint256 adminProposalId,
        uint256 newValue
    ) internal mustBeInitialized {
        require(newValue >= 0 && newValue <= 100, "CI:INVPT");
        __s().defaultProposalPassThreshold = newValue;
        _executeAdminProposal(address(this), msg.sender, adminProposalId);
    }

    function _isVotingBlacklisted(address account) internal view returns (bool) {
        return __s().votingBlacklistMap[account];
    }

    function _blacklistVoting(
        uint256 adminProposalId,
        address account,
        bool blacklist
    ) internal {
        __s().possibleVotingBlacklist.push(account);
        __s().votingBlacklistMap[account] = blacklist;
        _executeAdminProposal(address(this), msg.sender, adminProposalId);
    }

    function _isVotingExcluded(address account) internal view returns (bool) {
        return __s().votingExcludedMap[account];
    }

    function _excludeVoting(
        uint256 adminProposalId,
        address account,
        bool excluded
    ) internal {
        __s().possibleVotingExcluded.push(account);
        __s().votingExcludedMap[account] = excluded;
        _executeAdminProposal(address(this), msg.sender, adminProposalId);
    }

    function _getNrOfProposals() internal view returns (uint256) {
        return __s().proposalIdCounter;
    }

    function _getProposalInfo(
        uint256 proposalId
    ) internal view returns (
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
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        return (
            proposal.uri,
            proposal.startTs,
            proposal.expireTs,
            proposal.tags,
            proposal.referenceProposalId,
            proposal.admin,
            proposal.executed,
            proposal.finalized,
            proposal.finalizedTs,
            proposal.holderEligibilityThreshold,
            proposal.passThreshold
        );
    }

    function _getAdminProposalStats(
        uint256 adminProposalId
    ) internal view returns (
        // number of admins
        uint256,
        // list of admins approving the proposal
        address[] memory,
        // true if the proposal is passed
        bool
    ) {
        CouncilStorage.Proposal storage proposal = __getProposal(adminProposalId);
        require(proposal.admin, "CI:NAP");
        uint256 nrOfAdmins = AddressSetLib._getItemsCount(
            ConstantsLib.SET_ZONE_ID, ConstantsLib.ADMIN_SET_ID);
        bytes32 adminApprovalSetId = __getProposalSetId(adminProposalId, "ADMIN_APPROVAL");
        address[] memory approvingAdmins =
            AddressSetLib._getItems(ConstantsLib.SET_ZONE_ID, adminApprovalSetId);
        bool passed = approvingAdmins.length > (nrOfAdmins / 2);
        return (
            nrOfAdmins,
            approvingAdmins,
            passed
        );
    }

    function _getProposalStats(
        uint256 proposalId
    ) internal view returns (
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
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        address[] memory approvers =
            AddressSetLib._getItems(
                ConstantsLib.SET_ZONE_ID, __getProposalSetId(proposalId, "APPROVAL"));
        uint256[] memory approverBalances = new uint256[](approvers.length);
        uint256 approvalsBalanceSum = 0;
        for (uint256 i = 0; i < approvers.length; i++) {
            if (proposal.finalized) {
                approverBalances[i] = proposal.fixatedBalances[approvers[i]];
                approvalsBalanceSum += approverBalances[i];
            } else {
                if (!__s().votingBlacklistMap[approvers[i]]) {
                    approverBalances[i] = IERC20(__s().grantToken).balanceOf(approvers[i]);
                    approvalsBalanceSum += approverBalances[i];
                }
            }
        }
        address[] memory rejectors =
            AddressSetLib._getItems(
                ConstantsLib.SET_ZONE_ID, __getProposalSetId(proposalId, "REJECTION"));
        uint256[] memory rejectorBalances = new uint256[](rejectors.length);
        uint256 rejectorsBalanceSum = 0;
        for (uint256 i = 0; i < rejectors.length; i++) {
            if (proposal.finalized) {
                rejectorBalances[i] = proposal.fixatedBalances[rejectors[i]];
                rejectorsBalanceSum += rejectorBalances[i];
            } else {
                if (!__s().votingBlacklistMap[rejectors[i]]) {
                    rejectorBalances[i] = IERC20(__s().grantToken).balanceOf(rejectors[i]);
                    rejectorsBalanceSum += rejectorBalances[i];
                }
            }
        }
        uint256 nrOfCirculatingTokens = __getNrOfCirculatingTokens();
        require(nrOfCirculatingTokens > 0, "CI:ZNRCT");
        require(approvalsBalanceSum <= nrOfCirculatingTokens, "CI:GABS");
        uint256 ratio = (100 * approvalsBalanceSum) / nrOfCirculatingTokens;
        return (
            approvers,
            approverBalances,
            approvalsBalanceSum,
            rejectors,
            rejectorBalances,
            rejectorsBalanceSum,
            ratio == 100 || ratio > proposal.passThreshold
        );
    }

    function _getPendingProposals() internal view returns (uint256[] memory) {
        uint256 counter = 0;
        {
            for (uint256 proposalId = 1; proposalId <= __s().proposalIdCounter; proposalId++) {
                CouncilStorage.Proposal storage proposal = __s().proposals[proposalId];
                if (!proposal.finalized) {
                    counter += 1;
                }
            }
        }
        uint256[] memory proposals = new uint256[](counter);
        uint256 j = 0;
        {
            for (uint256 proposalId = 1; proposalId <= __s().proposalIdCounter; proposalId++) {
                CouncilStorage.Proposal storage proposal = __s().proposals[proposalId];
                if (!proposal.finalized) {
                    proposals[j] = proposalId;
                    j += 1;
                }
            }
        }
        return proposals;
    }

    function _getAccountProposals(
        address account,
        bool onlyPending
    ) internal view returns (uint256[] memory) {
        uint256 counter = 0;
        {
            for (uint256 proposalId = 1; proposalId <= __s().proposalIdCounter; proposalId++) {
                CouncilStorage.Proposal storage proposal = __s().proposals[proposalId];
                bytes32 approvalSetId = __getProposalSetId(proposalId, "APPROVAL");
                bytes32 rejectionSetId = __getProposalSetId(proposalId, "REJECTION");
                if (
                    !proposal.admin &&
                    (!onlyPending || !proposal.finalized) &&
                    (
                        AddressSetLib._hasItem(ConstantsLib.SET_ZONE_ID, approvalSetId, account) ||
                        AddressSetLib._hasItem(ConstantsLib.SET_ZONE_ID, rejectionSetId, account)
                    )
                ) {
                    counter += 1;
                }
            }
        }
        uint256[] memory proposals = new uint256[](counter);
        uint256 j = 0;
        {
            for (uint256 proposalId = 1; proposalId <= __s().proposalIdCounter; proposalId++) {
                CouncilStorage.Proposal storage proposal = __s().proposals[proposalId];
                bytes32 approvalSetId = __getProposalSetId(proposalId, "APPROVAL");
                bytes32 rejectionSetId = __getProposalSetId(proposalId, "REJECTION");
                if (
                    !proposal.admin &&
                    (!onlyPending || !proposal.finalized) &&
                    (
                        AddressSetLib._hasItem(ConstantsLib.SET_ZONE_ID, approvalSetId, account) ||
                        AddressSetLib._hasItem(ConstantsLib.SET_ZONE_ID, rejectionSetId, account)
                    )
                ) {
                    proposals[j] = proposalId;
                    j += 1;
                }
            }
        }
        return proposals;
    }

    function _getAccountProposalStats(
        uint256 proposalId,
        address account
    ) internal view returns (
        // true if approved
        bool,
        // true if rejected
        bool,
        // used balance to approve or reject
        uint256
    ) {
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        bytes32 approvalSetId = __getProposalSetId(proposalId, "APPROVAL");
        bytes32 rejectionSetId = __getProposalSetId(proposalId, "REJECTION");
        bool isApprover = AddressSetLib._hasItem(ConstantsLib.SET_ZONE_ID, approvalSetId, account);
        bool isRejector = AddressSetLib._hasItem(ConstantsLib.SET_ZONE_ID, rejectionSetId, account);
        uint256 balance = 0;
        if (isApprover || isRejector) {
            if (proposal.finalized) {
                balance = proposal.fixatedBalances[account];
            } else {
                balance = IERC20(__s().grantToken).balanceOf(account);
            }
        }
        return (isApprover, isRejector, balance);
    }

    function _createProposal(
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
    ) internal mustBeInitialized {
        if (admin) {
            __mustBeAdmin(msg.sender);
            FiatHandlerLib._pay(FiatHandlerInternal.PayParams(
                payErc20,
                payer,
                __s().feeCollectionAccount,
                __s().adminProposalCreationFeeMicroUSD,
                msg.value,
                true, // return the remainder
                true  // consider discount
            ));
        } else {
            __mustBeCreator(msg.sender);
            FiatHandlerLib._pay(FiatHandlerInternal.PayParams(
                payErc20,
                payer,
                __s().feeCollectionAccount,
                __s().proposalCreationFeeMicroUSD,
                msg.value,
                true, // return the remainder
                true  // consider discount
            ));
        }
        uint256 proposalId = __s().proposalIdCounter + 1;
        __s().proposalIdCounter += 1;
        CouncilStorage.Proposal storage proposal = __s().proposals[proposalId];
        proposal.uri = proposalURI;
        proposal.startTs = startTs;
        proposal.expireTs = expireTs;
        proposal.tags = tags;
        proposal.referenceProposalId = referenceProposalId;
        proposal.admin = admin;
        if (!admin) {
            proposal.holderEligibilityThreshold = __s().defaultHolderEligibilityThreshold;
            if (holderEligibilityThreshold > 0) {
                proposal.holderEligibilityThreshold = uint256(holderEligibilityThreshold);
            }
            proposal.passThreshold = __s().defaultProposalPassThreshold;
            if (passThreshold > 0) {
                proposal.passThreshold = uint256(passThreshold);
            }
        }
        emit NewProposal(proposalId);
    }

    function _updateProposal(
        uint256 proposalId,
        string memory proposalURI,
        uint256 startTs,
        uint256 expireTs,
        string[] memory tags,
        uint256 referenceProposalId
    ) internal mustBeInitialized {
        __mustBeAdmin(msg.sender);
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        require(!proposal.finalized, "CI:FNLZED");
        proposal.uri = proposalURI;
        proposal.startTs = startTs;
        proposal.expireTs = expireTs;
        proposal.tags = tags;
        proposal.referenceProposalId = referenceProposalId;
        emit ProposalUpdate(proposalId);
    }

    function _updateHolderEligibilityThreshold(
        uint256 proposalId,
        uint256 newValue
    ) internal mustBeInitialized {
        __mustBeAdmin(msg.sender);
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        require(!proposal.finalized, "CI:FNLZED");
         // we don't have such a threshold for admin proposals
        require(!proposal.admin, "CI:ADMNP");
        bytes32 approvalSetId = __getProposalSetId(proposalId, "APPROVAL");
        bytes32 rejectionSetId = __getProposalSetId(proposalId, "REJECTION");
        require(AddressSetLib._getItemsCount(
            ConstantsLib.SET_ZONE_ID, approvalSetId) == 0, "CI:NZA");
        require(AddressSetLib._getItemsCount(
            ConstantsLib.SET_ZONE_ID, rejectionSetId) == 0, "CI:NZR");
        proposal.holderEligibilityThreshold = newValue;
        emit ProposalUpdate(proposalId);
    }

    function _updatePassThreshold(
        uint256 proposalId,
        uint256 newValue
    ) internal mustBeInitialized {
        __mustBeAdmin(msg.sender);
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        require(!proposal.finalized, "CI:FNLZED");
         // we don't have such a threshold for admin proposals
        require(!proposal.admin, "CI:ADMNP");
        proposal.passThreshold = newValue;
        emit ProposalUpdate(proposalId);
    }

    function _approveProposal(
        uint256 proposalId
    ) internal mustBeInitialized {
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        /* solhint-disable not-rely-on-time */
        require(block.timestamp < proposal.expireTs, "CI:EXPRD");
        /* solhint-enable not-rely-on-time */
        require(!proposal.finalized, "CI:FNLZED");
        if (proposal.admin) {
            __mustBeAdmin(msg.sender);
            bytes32 adminApprovalSetId = __getProposalSetId(proposalId, "ADMIN_APPROVAL");
            if (AddressSetLib._addItem(ConstantsLib.SET_ZONE_ID, adminApprovalSetId, msg.sender)) {
                emit ProposalUpdate(proposalId);
            }
        } else {
            __mustBeEligibleHolder(proposalId, msg.sender);
            require(!__s().votingBlacklistMap[msg.sender], "CI:BLCK");
            bool updated = false;
            bytes32 approvalSetId = __getProposalSetId(proposalId, "APPROVAL");
            bytes32 rejectionSetId = __getProposalSetId(proposalId, "REJECTION");
            if (AddressSetLib._removeItem(ConstantsLib.SET_ZONE_ID, rejectionSetId, msg.sender)) {
                updated = true;
            }
            if (AddressSetLib._addItem(ConstantsLib.SET_ZONE_ID, approvalSetId, msg.sender)) {
                updated = true;
            }
            if (updated) {
                emit ProposalUpdate(proposalId);
            }
        }
    }

    function _withdrawProposalApproval(
        uint256 proposalId
    ) internal mustBeInitialized {
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        /* solhint-disable not-rely-on-time */
        require(block.timestamp < proposal.expireTs, "CI:EXPRD");
        /* solhint-enable not-rely-on-time */
        require(!proposal.finalized, "CI:FNLZED");
        if (proposal.admin) {
            __mustBeAdmin(msg.sender);
            bytes32 adminApprovalSetId = __getProposalSetId(proposalId, "ADMIN_APPROVAL");
            if (AddressSetLib._removeItem(ConstantsLib.SET_ZONE_ID, adminApprovalSetId, msg.sender)) {
                emit ProposalUpdate(proposalId);
            }
        } else {
            // NOTE: we dissallow any grant-token transfer when there is an approval or
            //       rejection for a non-finalized proposal. Therefore, the following
            //       condition MUST hold.
            __mustBeEligibleHolder(proposalId, msg.sender);
            bytes32 approvalSetId = __getProposalSetId(proposalId, "APPROVAL");
            if (AddressSetLib._removeItem(ConstantsLib.SET_ZONE_ID, approvalSetId, msg.sender)) {
                emit ProposalUpdate(proposalId);
            }
        }
    }

    function _rejectProposal(
        uint256 proposalId
    ) internal mustBeInitialized {
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        /* solhint-disable not-rely-on-time */
        require(block.timestamp < proposal.expireTs, "CI:EXPRD");
        /* solhint-enable not-rely-on-time */
        require(!proposal.finalized, "CI:FNLZED");
        require(!proposal.admin, "CI:ADMINP");
        __mustBeEligibleHolder(proposalId, msg.sender);
        require(!__s().votingBlacklistMap[msg.sender], "CI:BLCK");
        bytes32 approvalSetId = __getProposalSetId(proposalId, "APPROVAL");
        bytes32 rejectionSetId = __getProposalSetId(proposalId, "REJECTION");
        bool updated = false;
        if (AddressSetLib._removeItem(ConstantsLib.SET_ZONE_ID, approvalSetId, msg.sender)) {
            updated = true;
        }
        if (AddressSetLib._addItem(ConstantsLib.SET_ZONE_ID, rejectionSetId, msg.sender)) {
            updated = true;
        }
        if (updated) {
            emit ProposalUpdate(proposalId);
        }
    }

    function _withdrawProposalRejection(
        uint256 proposalId
    ) internal mustBeInitialized {
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        /* solhint-disable not-rely-on-time */
        require(block.timestamp < proposal.expireTs, "CI:EXPRD");
        /* solhint-enable not-rely-on-time */
        require(!proposal.finalized, "CI:FNLZED");
        require(!proposal.admin, "CI:ADMINP");
        // NOTE: we dissallow any grant-token transfer when there is an approval or
        //       rejection for a non-finalized proposal. Therefore, the following
        //       condition MUST hold.
        __mustBeEligibleHolder(proposalId, msg.sender);
        bytes32 rejectionSetId = __getProposalSetId(proposalId, "REJECTION");
        if (AddressSetLib._removeItem(ConstantsLib.SET_ZONE_ID, rejectionSetId, msg.sender)) {
            emit ProposalUpdate(proposalId);
        }
    }

    function _finalizeProposal(
        uint256 proposalId
    ) internal mustBeInitialized {
        __mustBeAdmin(msg.sender);
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        require(!proposal.finalized, "CI:FNLZED");
        __finalize(proposalId);
    }

    function _executeAdminProposal(
        address caller,
        address executor,
        uint256 adminProposalId
    ) internal mustBeInitialized {
        __mustBeFinalizer(caller);
        __mustBeAdmin(executor);
        CouncilStorage.Proposal storage proposal = __getProposal(adminProposalId);
        require(proposal.admin, "CI:NADMNP");
        require(!proposal.finalized, "CI:FNLZED");
        require(!proposal.executed, "CI:EXECED");
        __finalize(adminProposalId);
        uint256 nrOfAdmins = AddressSetLib._getItemsCount(
            ConstantsLib.SET_ZONE_ID, ConstantsLib.ADMIN_SET_ID);
        bytes32 adminApprovalSetId = __getProposalSetId(adminProposalId, "ADMIN_APPROVAL");
        address[] memory approvingAdmins =
            AddressSetLib._getItems(ConstantsLib.SET_ZONE_ID, adminApprovalSetId);
        bool passed = approvingAdmins.length > (nrOfAdmins / 2);
        require(passed, "CI:NPASSED");
        proposal.executed = true;
        emit ProposalExecuted(adminProposalId);
    }

    function _executeProposal(
        address caller,
        address executor,
        uint256 proposalId
    ) internal mustBeInitialized {
        __mustBeFinalizer(caller);
        __mustBeExecutor(executor);
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        require(!proposal.admin, "CI:ADMNP");
        require(!proposal.finalized, "CI:FNLZED");
        require(!proposal.executed, "CI:EXECED");
        __finalize(proposalId);
        bytes32 approvalSetId = __getProposalSetId(proposalId, "APPROVAL");
        address[] memory approvers = AddressSetLib._getItems(
            ConstantsLib.SET_ZONE_ID, approvalSetId);
        uint256 approvalsBalanceSum = 0;
        for (uint256 i = 0; i < approvers.length; i++) {
            if (!__s().votingBlacklistMap[approvers[i]]) {
                approvalsBalanceSum += proposal.fixatedBalances[approvers[i]];
            }
        }
        uint256 nrOfCirculatingTokens = __getNrOfCirculatingTokens();
        require(nrOfCirculatingTokens > 0, "CI:ZNRCT");
        require(approvalsBalanceSum <= nrOfCirculatingTokens, "CI:GABS");
        uint256 ratio = (100 * approvalsBalanceSum) / nrOfCirculatingTokens;
        bool passed = ratio == 100 || ratio > proposal.passThreshold;
        require(passed, "CI:NPASSED");
        proposal.executed = true;
        emit ProposalExecuted(proposalId);
    }

    function _transferTokensFromCouncil(
        uint256 adminProposalId,
        address to,
        uint256 amount
    ) internal mustBeInitialized {
        IERC20(__s().grantToken).transferFrom(address(this), to, amount);
        _executeAdminProposal(address(this), msg.sender, adminProposalId);
    }

    function _icoTransferTokensFromCouncil(
        address payErc20,
        address payer,
        address to,
        uint256 nrOfTokens
    ) internal mustBeInitialized {
        require(__s().icoPhase, "CI:NICO");
        require(__s().icoTokenPriceMicroUSD > 0, "CI:NICOP");
        IERC20(__s().grantToken).transferFrom(address(this), to, nrOfTokens);
        uint256 spentWei = FiatHandlerLib._pay(FiatHandlerInternal.PayParams(
            payErc20,
            payer,
            __s().feeCollectionAccount,
            __s().icoFeeMicroUSD,
            msg.value,
            false, // do not return the remainder
            false  // do not consider discount
        ));
        FiatHandlerLib._pay(FiatHandlerInternal.PayParams(
            payErc20,
            payer,
            __s().icoCollectionAccount,
            nrOfTokens * __s().icoTokenPriceMicroUSD,
            msg.value - spentWei,
            true, // return the remainder
            true  // consider discount
        ));
    }

    function __mustBeAdmin(address account) private view {
        require(BoardLib._isOperator(ConstantsLib.OPERATOR_TYPE_ADMIN, account), "CI:NA");
    }

    function __mustBeCreator(address account) private view {
        require(BoardLib._isOperator(ConstantsLib.OPERATOR_TYPE_CREATOR, account), "CI:NC");
    }

    function __mustBeExecutor(address account) private view {
        require(BoardLib._isOperator(ConstantsLib.OPERATOR_TYPE_EXECUTOR, account), "CI:NE");
    }

    function __mustBeFinalizer(address account) private view {
        require(
            account == address(this) ||
                BoardLib._isOperator(ConstantsLib.OPERATOR_TYPE_FINALIZER, account)
            , "CI:NF"
        );
    }

    function __mustBeEligibleHolder(uint256 proposalId, address account) private view {
        uint256 accountBalance = IERC20(__s().grantToken).balanceOf(account);
        uint256 ratio = (100 * accountBalance) / IERC20(__s().grantToken).totalSupply();
        require(ratio >= __s().proposals[proposalId].holderEligibilityThreshold, "CI:NELGH");
    }

    function __getProposal(
        uint256 proposalId
    ) private view returns (CouncilStorage.Proposal storage) {
        require(proposalId > 0 && proposalId <= __s().proposalIdCounter, "CI:PNF");
        return __s().proposals[proposalId];
    }

    function __getProposalSetId(
        uint256 proposalId,
        string memory voteCategory
    ) private pure returns (bytes32) {
        for(uint256 i = 1; i <= 10; i++) {
            bytes32 hash = HasherLib._mixHash4(
                HasherLib._hashStr("PROPOSAL_ID"),
                HasherLib._hashInt(proposalId),
                HasherLib._hashStr(voteCategory),
                HasherLib._hashInt(i)
            );
            if (uint256(hash) > 100) {
              return hash;
            }
        }
        revert("CI:SWW");
    }

    function __finalize(uint256 proposalId) private {
        CouncilStorage.Proposal storage proposal = __getProposal(proposalId);
        if (!proposal.admin) {
            bytes32 approvalSetId = __getProposalSetId(proposalId, "APPROVAL");
            bytes32 rejectionSetId = __getProposalSetId(proposalId, "REJECTION");
            address[] memory approvers = AddressSetLib._getItems(
                ConstantsLib.SET_ZONE_ID, approvalSetId);
            for (uint256 i = 0; i < approvers.length; i++) {
                address account = approvers[i];
                proposal.fixatedBalances[account] =
                    IERC20(__s().grantToken).balanceOf(account);
            }
            address[] memory rejectors = AddressSetLib._getItems(
                ConstantsLib.SET_ZONE_ID, rejectionSetId);
            for (uint256 i = 0; i < rejectors.length; i++) {
                address account = rejectors[i];
                proposal.fixatedBalances[account] =
                    IERC20(__s().grantToken).balanceOf(account);
            }
        }
        proposal.finalized = true;
        /* solhint-disable not-rely-on-time */
        proposal.finalizedTs = block.timestamp;
        /* solhint-enable not-rely-on-time */
        emit ProposalFinalized(proposalId);
    }

    function __getNrOfCirculatingTokens() private view returns (uint256) {
        IERC20 grantToken = IERC20(__s().grantToken);
        uint256 nrOfTokens = grantToken.totalSupply();
        for (uint256 i = 0; nrOfTokens > 0 && i < __s().possibleVotingExcluded.length; i++) {
            address account = __s().possibleVotingExcluded[i];
            if (__s().votingExcludedMap[account]) {
                uint256 balance = grantToken.balanceOf(account);
                require(balance <= nrOfTokens, "CI:GB");
                nrOfTokens -= balance;
            }
        }
        return nrOfTokens;
    }

    function __s() private pure returns (CouncilStorage.Layout storage) {
        return CouncilStorage.layout();
    }
}

