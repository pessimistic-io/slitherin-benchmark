// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AggregatorV3Interface.sol";

interface IUsdPlusToken{
    function liquidityIndex() external view returns(uint256);
}

contract OvernightChainlink{
    AggregatorV3Interface public tokenChaink;
    address public usdPlusToken;
    uint8 public decimals;
    string public description;

    constructor(string memory _description, AggregatorV3Interface _tokenChaink, address _usdPlusToken) {
        description = _description;
        tokenChaink = _tokenChaink;
        usdPlusToken = _usdPlusToken;
        decimals = tokenChaink.decimals();
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = tokenChaink.latestRoundData();
        answer = int(uint256(answer) * liquidityIndex() / 10 ** 27);
    }

    function liquidityIndex() public view returns(uint256 index){
        index = IUsdPlusToken(usdPlusToken).liquidityIndex();
    }

}

