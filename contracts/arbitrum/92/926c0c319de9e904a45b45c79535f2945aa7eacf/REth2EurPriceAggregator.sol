// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./AggregatorV3Interface.sol";

import "./IRETH.sol";

/*
 * @notice Returns the EUR price for 1 rETH.
 *
 * @dev Queries the rETH token for its rETH value/rate; then queries the rETH:ETH and ETH:EUR oracle for the price, and
 *      multiplies the results.
 */
contract REth2EurPriceAggregator is AggregatorV3Interface {
    AggregatorV3Interface rETHETHFeed;
    AggregatorV3Interface ETHUSDFeed;
    AggregatorV3Interface EURUSDFeed;
    uint8 rETHETHDecimals;
    uint8 ETHUSDDecimals;
    uint8 EURUSDDecimals;

    constructor(address _rethEthOracle, address _ethUsdOracle, address _eurUsdOracle) {
        rETHETHFeed = AggregatorV3Interface(_rethEthOracle);
        ETHUSDFeed = AggregatorV3Interface(_ethUsdOracle);
        EURUSDFeed = AggregatorV3Interface(_eurUsdOracle);

        // Getting the decimals from each feed
        rETHETHDecimals = rETHETHFeed.decimals();
        ETHUSDDecimals = ETHUSDFeed.decimals();
        EURUSDDecimals = EURUSDFeed.decimals();
    }

    function latestRoundData()
        public
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // Getting the latest round data from each feed
        (, int256 rETHETHRate, uint256 startedAt_rETHETH, uint256 updatedAt_rETHETH,) = rETHETHFeed.latestRoundData();
        (, int256 ETHUSDRate, uint256 startedAt_ETHUSD, uint256 updatedAt_ETHUSD,) = ETHUSDFeed.latestRoundData();
        (, int256 EURUSDRate, uint256 startedAt_EURUSD, uint256 updatedAt_EURUSD,) = EURUSDFeed.latestRoundData();

        // Normalize the rates to 18 decimals
        rETHETHRate *= int256(10) ** (18 - rETHETHDecimals);
        ETHUSDRate *= int256(10) ** (18 - ETHUSDDecimals);
        EURUSDRate *= int256(10) ** (18 - EURUSDDecimals);

        // Calculate the rETH:EUR rate:
        answer = (rETHETHRate * ETHUSDRate) / EURUSDRate;

        // Earliest startedAt and updatedAt from all feeds
        startedAt = min(startedAt_rETHETH, min(startedAt_ETHUSD, startedAt_EURUSD));
        updatedAt = min(updatedAt_rETHETH, min(updatedAt_ETHUSD, updatedAt_EURUSD));

        // Note: Other return values are set to 0 for simplicity.
        roundId = 0;
        answeredInRound = 0;
    }

    function getRoundData(uint80)
        public
        pure
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // Throw immediately due to combining price feeds with varied roundIds
        // Query not possible
        require(1 == 0, "No data present");

        // Suppress unused variables warning
        roundId = 0;
        answer = 0;
        startedAt = 0;
        updatedAt = 0;
        answeredInRound = 0;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    // Implementing other functions from AggregatorV3Interface to satisfy the interface requirements
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function description() public pure override returns (string memory) {
        return "rETH to EUR Price Feed";
    }

    function version() public pure override returns (uint256) {
        return 1;
    }
}

