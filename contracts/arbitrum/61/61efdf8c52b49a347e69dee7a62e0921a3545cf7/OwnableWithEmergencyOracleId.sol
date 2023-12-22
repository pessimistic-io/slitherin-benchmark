// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "./Ownable.sol";

import "./IOracleAggregator.sol";

/**
    Error codes:
    - O1 = Only when no data and after timestamp allowed
    - O2 = Only when no data and after emergency period allowed
 */
contract OwnableWithEmergencyOracleId is Ownable {
    // Opium
    IOracleAggregator public oracleAggregator;

    // Governance
    uint256 public emergencyPeriod;

    constructor(IOracleAggregator _oracleAggregator, uint256 _emergencyPeriod) {
        // Opium
        oracleAggregator = _oracleAggregator;

        // Governance
        emergencyPeriod = _emergencyPeriod;
    }

    /** RESOLVER */
    function __callback(uint256 _timestamp, uint256 _result) internal {
        require(
            !oracleAggregator.hasData(address(this), _timestamp) &&
            _timestamp <= block.timestamp,
            "O1"
        );

        oracleAggregator.__callback(_timestamp, _result);
    }

    /** GOVERNANCE */
    /** 
        Emergency callback allows to push data manually in case `emergencyPeriod` elapsed and no data were provided
    */
    function emergencyCallback(uint256 _timestamp, uint256 _result) external onlyOwner {
        require(
            !oracleAggregator.hasData(address(this), _timestamp) &&
            _timestamp + emergencyPeriod <= block.timestamp,
            "O2"
        );

        oracleAggregator.__callback(_timestamp, _result);
    }

    function setEmergencyPeriod(uint256 _newEmergencyPeriod) external onlyOwner {
        emergencyPeriod = _newEmergencyPeriod;
    }
}

