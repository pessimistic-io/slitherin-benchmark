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

/// @author Kam Amini <kam@arteq.io>
///
/// @notice Use at your own risk. Just got the basic
///         idea from: https://github.com/solidstate-network/solidstate-solidity
library CouncilStorage {

    struct Proposal {

        bool admin;
        string uri;
        string[] tags;

        uint256 startTs;
        uint256 expireTs;
        uint256 finalizedTs;

        uint256 referenceProposalId;

        bool executed;
        bool finalized;

        // vvv used only in non-admin proposals vvv

        // percentage of the holder ownership to
        // the total number of grant tokens
        uint256 holderEligibilityThreshold;
        // percentage of the approved total balance to
        // the total number of grant tokens
        uint256 passThreshold;

        // the mapping of balances at the time of finalization
        mapping(address => uint256) fixatedBalances;

        // reserved for future usage
        mapping(bytes32 => bytes) extra;
    }

    struct Layout {

        bool initialized;

        address registrar;
        uint256 registereeId;
        address grantToken;

        uint256 proposalIdCounter;
        mapping(uint256 => Proposal) proposals;

        // percentage of the holder ownership to
        // the total number of grant tokens
        uint256 defaultHolderEligibilityThreshold;
        // percentage of the approved total balance to
        // the total number of grant tokens
        uint256 defaultProposalPassThreshold;

        // ETH fee to be collected for each proposal creation
        uint256 proposalCreationFeeMicroUSD;

        // ETH fee to be collected for each admin proposal creation
        uint256 adminProposalCreationFeeMicroUSD;

        address feeCollectionAccount;
        address icoCollectionAccount;

        bool icoPhase;
        uint256 icoTokenPriceMicroUSD;
        uint256 icoFeeMicroUSD;

        address[] possibleVotingBlacklist;
        mapping(address => bool) votingBlacklistMap;

        address[] possibleVotingExcluded;
        mapping(address => bool) votingExcludedMap;

        // reserved for future usage
        mapping(bytes32 => bytes) extra;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("qomet-tech.contracts.facets.txn.council.storage");

    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        /* solhint-disable no-inline-assembly */
        assembly {
            s.slot := slot
        }
        /* solhint-enable no-inline-assembly */
    }
}

