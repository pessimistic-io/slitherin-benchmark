// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title   Price Feeds Data Consumer
 * @author  Pulsar Finance
 * @dev     VERSION: 1.0
 *          DATE:    2023.10.05
 */

import {Errors} from "./Errors.sol";
import {IPriceFeedsDataConsumer} from "./IPriceFeedsDataConsumer.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

contract PriceFeedsDataConsumer is IPriceFeedsDataConsumer {
    AggregatorV3Interface public nativeTokenDataFeed;

    constructor(address _nativeTokenOracleAddress) {
        nativeTokenDataFeed = AggregatorV3Interface(_nativeTokenOracleAddress);
    }

    function getDataFeedLatestPriceAndDecimals(
        address oracleAddress
    ) external view returns (uint256 answer, uint256 decimals) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(oracleAddress);
        // prettier-ignore
        (
            /* uint80 roundID */,
            int256 answerRaw,
            /*uint256 startedAt*/,
            /*uint256 timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        uint8 decimalsRaw = dataFeed.decimals();
        if (answerRaw <= 0 || decimalsRaw <= 0) {
            revert Errors.PriceFeedError(
                "Price feed returned zero or negative values"
            );
        }
        answer = uint256(answerRaw);
        decimals = uint256(decimalsRaw);
    }

    function getNativeTokenDataFeedLatestPriceAndDecimals()
        external
        view
        returns (uint256 answer, uint256 decimals)
    {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int256 answerRaw,
            /*uint256 startedAt*/,
            /*uint256 timeStamp*/,
            /*uint80 answeredInRound*/
        ) = nativeTokenDataFeed.latestRoundData();
        uint8 decimalsRaw = nativeTokenDataFeed.decimals();
        answer = uint256(answerRaw);
        decimals = uint256(decimalsRaw);
    }
}

