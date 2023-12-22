// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

abstract contract VotingParameters {
    // Status parameters for a voting
    uint256 internal constant INIT_STATUS = 0;
    uint256 internal constant PENDING_STATUS = 1;
    uint256 internal constant VOTING_STATUS = 2;
    uint256 internal constant SETTLED_STATUS = 3;
    uint256 internal constant CLOSE_STATUS = 404;

    // Result parameters for a voting
    uint256 internal constant INIT_RESULT = 0;
    uint256 internal constant PASS_RESULT = 1;
    uint256 internal constant REJECT_RESULT = 2;
    uint256 internal constant TIED_RESULT = 3;
    uint256 internal constant FAILED_RESULT = 4;

    // Voting choices
    uint256 internal constant VOTE_FOR = 1;
    uint256 internal constant VOTE_AGAINST = 2;
}

