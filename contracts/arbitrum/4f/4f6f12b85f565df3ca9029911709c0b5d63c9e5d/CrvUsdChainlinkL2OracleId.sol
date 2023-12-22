// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "./AggregatorV3Interface.sol";
import "./FlagsInterface.sol";

import "./ILiveFeedOracleId.sol";
import "./OwnableWithEmergencyOracleId.sol";

/**
    Error codes:
    - C1 = Chainlink feeds are not being updated
 */
contract CrvUsdChainlinkL2OracleId is ILiveFeedOracleId, OwnableWithEmergencyOracleId {
    // Chainlink
    address constant private FLAG_ARBITRUM_SEQ_OFFLINE = address(bytes20(bytes32(uint256(keccak256("chainlink.flags.arbitrum-seq-offline")) - 1)));
    AggregatorV3Interface public priceFeed;
    FlagsInterface public chainlinkFlags;

    constructor(
        IOracleAggregator _oracleAggregator,
        uint256 _emergencyPeriod,
        AggregatorV3Interface _priceFeed,
        FlagsInterface _chainlinkFlags
    ) OwnableWithEmergencyOracleId(_oracleAggregator, _emergencyPeriod) {
        priceFeed = _priceFeed;
        chainlinkFlags = _chainlinkFlags;

        /*
        {
            "author": "Opium.Team",
            "description": "CRV/USD Oracle ID",
            "asset": "CRV/USD",
            "type": "onchain",
            "source": "chainlink",
            "logic": "none",
            "path": "latestAnswer()"
        }
        */
        emit LogMetadataSet("{\"author\":\"Opium.Team\",\"description\":\"CRV/USD Oracle ID\",\"asset\":\"CRV/USD\",\"type\":\"onchain\",\"source\":\"chainlink\",\"logic\":\"none\",\"path\":\"latestAnswer()\"}");
    }

    /** CHAINLINK */
    function getResult() public view override returns (uint256) {
        // Don't raise flag by default
        bool isRaised = false;

        // Check if flags contract was set and write flag value
        if (address(chainlinkFlags) != address(0)) {
            isRaised = chainlinkFlags.getFlag(FLAG_ARBITRUM_SEQ_OFFLINE);
        }

        // If flag was raised, revert
        if (isRaised) {
            revert ("C1");
        }

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

    function setChainlinkFlags(FlagsInterface _chainlinkFlags) external onlyOwner {
        chainlinkFlags = _chainlinkFlags;
    }
}

