// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./VotingParameters.sol";

abstract contract OnboardProposalParameters is VotingParameters {
    // TODO: Parameters for test
    //       2 hours for fujiInternal, 18 hours for fuji
    uint256 public constant PROPOSAL_VOTING_PERIOD = 3 days;

    // DEG threshold for starting a report
    // TODO: Different threshold for test and mainnet
    uint256 public constant PROPOSE_THRESHOLD = 0;

    // 10000 = 100%
    uint256 public constant MAX_CAPACITY_RATIO = 10000;
}

