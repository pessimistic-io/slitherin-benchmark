// SPDX-License-Identifier: AGPL V3.0
pragma solidity 0.8.4;

interface IStrategy {
    function withdraw(uint256) external returns (uint256, uint256);

    function harvest() external;

    function getFundingRate() external view returns (int256);

    function setKeeper(address) external;
}

