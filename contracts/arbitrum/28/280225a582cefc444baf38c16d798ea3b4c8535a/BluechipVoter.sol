// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./VoterV2_1.sol";

contract BluechipVoter is VoterV2_1 {
    // just renamed voterV2_1, all same functions

    constructor(
        address __ve, 
        address _factory, 
        address _gauges, 
        address _fees_collector,
        address _lzEndpoint
    ) VoterV2_1(__ve, _factory, _gauges, _fees_collector, _lzEndpoint) {}
}

