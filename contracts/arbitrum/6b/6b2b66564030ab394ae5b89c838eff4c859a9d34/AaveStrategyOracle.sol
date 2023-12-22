pragma solidity ^0.8.7;

import "./AggregatorV3Interface.sol";

import "./console.sol";

contract AaveStrategyOracle {
    AggregatorV3Interface internal dataFeed;

    constructor(address priceFeedAddress) {
        dataFeed = AggregatorV3Interface(
            priceFeedAddress
        );
    }


    function tokenAmount(uint256 usdAmount) public view returns (uint256) {
        uint256 usdcUsdPrice = uint256(_getLatestData());
        uint256 amountToken = usdAmount * 1e6 / usdcUsdPrice;

        return amountToken;
    }

    function _getLatestData() internal view returns (int) {
        (,int answer,,,) = dataFeed.latestRoundData();

        return answer;
    }
}
