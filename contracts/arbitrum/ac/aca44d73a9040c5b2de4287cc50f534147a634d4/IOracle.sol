// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IOracle {
    function getLatestRoundData()
        external
        view
        returns (uint256 timestamp, uint256 price);

    function pairName() external view returns (string memory);

    function isWritable() external view returns (bool);

    function writePrice(uint256 timestamp, uint256 price) external;
}

