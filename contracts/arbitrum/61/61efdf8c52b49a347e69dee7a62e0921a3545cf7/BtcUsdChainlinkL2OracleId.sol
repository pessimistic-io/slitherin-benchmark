// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "./AggregatorV3Interface.sol";

import "./ILiveFeedOracleId.sol";
import "./OwnableWithEmergencyOracleId.sol";

contract BtcUsdChainlinkL2OracleId is ILiveFeedOracleId, OwnableWithEmergencyOracleId {
    // Chainlink
    AggregatorV3Interface public priceFeed;

    constructor(
        IOracleAggregator _oracleAggregator,
        uint256 _emergencyPeriod,
        AggregatorV3Interface _priceFeed
    ) OwnableWithEmergencyOracleId(_oracleAggregator, _emergencyPeriod) {
        priceFeed = _priceFeed;

        /*
        {
            "author": "Opium.Team",
            "description": "BTC/USD Oracle ID",
            "asset": "BTC/USD",
            "type": "onchain",
            "source": "chainlink",
            "logic": "none",
            "path": "latestAnswer()"
        }
        */
        emit LogMetadataSet("{\"author\":\"Opium.Team\",\"description\":\"BTC/USD Oracle ID\",\"asset\":\"BTC/USD\",\"type\":\"onchain\",\"source\":\"chainlink\",\"logic\":\"none\",\"path\":\"latestAnswer()\"}");
    }

    /** CHAINLINK */
    function getResult() public view override returns (uint256) {
        ( , int256 price, , , ) = priceFeed.latestRoundData();

        // Data are provided with 8 decimals, adjust to 18 decimals
        uint256 result = uint256(price) * 1e10;

        return result;
    }
  
    /** RESOLVER */
    function _callback(uint256 _timestamp) external override {
        uint256 result = getResult();
        __callback(_timestamp, result);
    }

    /** GOVERNANCE */
    function setPriceFeed(AggregatorV3Interface _priceFeed) external onlyOwner {
        priceFeed = _priceFeed;
    }
}

