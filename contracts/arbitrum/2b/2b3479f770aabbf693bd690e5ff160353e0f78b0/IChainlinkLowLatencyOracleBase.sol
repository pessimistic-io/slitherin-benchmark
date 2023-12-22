// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "./IVerifierProxy.sol";

struct OracleLookupData {
    string feedLabel;
    string[] feeds;
    string queryLabel;
}

struct ReportsData {
    int256 cviValue;
    uint256 eventTimestamp;
}

interface IChainlinkLowLatencyOracleBase {
    error OracleLookup(string feedLabel, string[] feeds, string queryLabel, uint256 query, bytes data);

    function setVerifier(IVerifierProxy verifier) external;
}
