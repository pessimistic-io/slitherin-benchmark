// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IOracle} from "./IOracle.sol";
import {ISushiSwapV2Pair} from "./ISushiSwapV2Pair.sol";
import {IERC20} from "./IERC20.sol";
import {SafeMath} from "./SafeMath.sol";

import {FixedPrice} from "./FixedPrice.sol";
import {VersionedInitializable} from "./VersionedInitializable.sol";

contract ChainlinkFixedPriceOracle is
    FixedPrice,
    AggregatorV3Interface,
    VersionedInitializable
{
    using SafeMath for uint256;

    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 timestamp;
        bool success;
        uint8 decimals;
    }

    function initialize(
        string memory _name,
        uint256 startingPrice,
        address _governance
    ) external initializer {
        _initialize(_name, startingPrice, _governance);
    }

    function decimals() external pure override returns (uint8) {
        return uint8(getDecimalPercision());
    }

    function description() external pure override returns (string memory) {
        return "A custom pricefeed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRevision() public pure override returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, int256(fetchPrice()), 0, block.timestamp, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, int256(fetchPrice()), 0, block.timestamp, 1);
    }

    function latestAnswer() external view override returns (int256) {
        return int256(fetchPrice());
    }

    function latestTimestamp() external view override returns (uint256) {
        return block.timestamp;
    }

    function latestRound() external view override returns (uint256) {
        return block.timestamp;
    }

    function getAnswer(uint256) external view override returns (int256) {
        return int256(fetchPrice());
    }

    function getTimestamp(uint256) external view override returns (uint256) {
        return block.timestamp;
    }
}

