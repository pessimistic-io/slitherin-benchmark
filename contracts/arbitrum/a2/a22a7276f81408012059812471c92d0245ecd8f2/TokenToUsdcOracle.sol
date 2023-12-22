pragma solidity ^0.8.7;

import "./AggregatorV3Interface.sol";

import "./ITokenToUsdcOracle.sol";

contract TokenToUsdcOracle is ITokenToUsdcOracle {
    AggregatorV3Interface internal dataFeed;
    AggregatorV3Interface internal usdcDataFeed;
    uint256 decimals;

    // if token decimals 18 need pass _decimals arg as 1e18
    constructor(address priceFeedAddress, address usdcPriceFeedAddress, uint256 _decimals) {
        dataFeed = AggregatorV3Interface(
            priceFeedAddress
        );
        usdcDataFeed = AggregatorV3Interface(
            usdcPriceFeedAddress
        );
        decimals = _decimals;
    }

    function usdcAmount(uint256 tokenAmount) external view override returns (uint256 amount) {
        uint256 tokenPrice = uint256(_getLatestData());
        uint256 usdcPrice = uint256(_getLatestUsdcData());
        uint256 usdAmount = tokenAmount * tokenPrice / decimals;
        amount = usdAmount * 1e6 / usdcPrice;

        return amount;
    }

    function _getLatestData() internal view returns (int) {
        (,int answer,,,) = dataFeed.latestRoundData();

        return answer;
    }

    function _getLatestUsdcData() internal view returns (int) {
        (,int answer,,,) = usdcDataFeed.latestRoundData();

        return answer;
    }
}

