// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

interface IChainlinkDataFeed is AggregatorV3Interface {
    function description() external view returns (string memory);
    function decimals() external view returns (uint8);
    function lastRoundId() external view returns (uint80);
    function version() external view returns (uint256);
    function checkAccess() external view returns (bool);
    function chargeAccessFee() external view returns (bool);
    function accessFee() external view returns (uint256);
    function authorized() external view returns (address);
    function accessList(address account) external view returns (bool);
    function addRound(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) external;
    function getRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
