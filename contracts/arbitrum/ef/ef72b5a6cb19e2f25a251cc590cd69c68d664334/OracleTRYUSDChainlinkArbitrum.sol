// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "./AggregatorV3Interface.sol";

import "./BaseOracleChainlinkMultiTwoFeeds.sol";

/// @title OracleTRYUSDChainlinkArbitrum
/// @author Angle Labs, Inc.
/// @notice Gives the price of BTC in Euro in base 18
/// @dev This contract is built to be deployed on Arbitrum
contract OracleTRYUSDChainlinkArbitrum is BaseOracleChainlinkMultiTwoFeeds {
    string public constant DESCRIPTION = "TRY/USD Oracle";

    constructor(uint32 _stalePeriod, address _treasury) BaseOracleChainlinkMultiTwoFeeds(_stalePeriod, _treasury) {}

    /// @inheritdoc IOracle
    function circuitChainlink() public pure override returns (AggregatorV3Interface[] memory) {
        AggregatorV3Interface[] memory _circuitChainlink = new AggregatorV3Interface[](1);
        // Oracle TRY/USD
        _circuitChainlink[0] = AggregatorV3Interface(0xE8f8AfE4b56c6C421F691bfAc225cE61b2C7CD05);
        return _circuitChainlink;
    }
}

