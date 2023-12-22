pragma solidity ^0.8.0;

import "./AggregatorV3Interface.sol";

contract Price8Decimal {
    AggregatorV3Interface immutable feed;

    constructor(address _feed) {
        feed = AggregatorV3Interface(_feed);
    }

    /// @dev chainlink returns 8-decimal fixed-point, convert to 18-decimal
    function get() public view returns (uint) {
        (, int price, , , ) = feed.latestRoundData();
        return uint(price) * 10**10;
    }
}
