// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./AggregatorV3Interface.sol";

contract GarbiOracle is Ownable {

    using SafeMath for uint256;

    mapping(address => AggregatorV3Interface) public priceFeed;

    function setPriceFeedContract(address token, AggregatorV3Interface _priceFeed) public onlyOwner {
        require(token != address(0), "INVALID_TOKEN");
        priceFeed[token] = AggregatorV3Interface(
            _priceFeed
        );
    }

    function getLatestPrice(address token) public view returns (uint256) {
        (
            ,
            /*uint80 roundID*/ int price /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = priceFeed[token].latestRoundData();
        return uint256(price);
    }
}
