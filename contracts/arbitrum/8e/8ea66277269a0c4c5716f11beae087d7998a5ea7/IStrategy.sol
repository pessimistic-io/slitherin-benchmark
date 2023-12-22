// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

interface IStrategy {
    function name() external view returns (string memory);
    function rate(uint256) external view returns (uint256);
    function mint(uint256 amt) external returns (uint256);
    function burn(uint256 amt) external returns (uint256);
}

