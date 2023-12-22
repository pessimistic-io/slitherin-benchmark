// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

interface IInvestor {
    function life(uint256) external view returns (uint256);
    function positions(uint256) external view returns (address, address, address, uint256, uint256, uint256);
    function earn(address, address, address, uint256, uint256, bytes calldata) external returns (uint256);
    function sell(uint256, uint256, uint256, bytes calldata) external;
    function save(uint256, uint256, bytes calldata) external;
    function kill(uint256, bytes calldata) external;
}

