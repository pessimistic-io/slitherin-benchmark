// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

interface IPriceProtectionTaxCalculator {
    event KeeperUpdated(address keeper);
    event PriceUpdated(uint256 timestamp, uint256 price);
    event GrvPriceWeightUpdated(uint256[] weights);

    function setGrvPrice(uint256 timestamp, uint256 price) external;

    function setGrvPriceWeight(uint256[] calldata weights) external;

    function getGrvPrice(uint256 timestamp) external view returns (uint256);

    function referencePrice() external view returns (uint256);

    function startOfDay(uint256 timestamp) external pure returns (uint256);
}

