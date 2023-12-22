// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

interface IStrategy {
    function name() external view returns (string memory);
    function cap() external view returns (uint256);
    function status() external view returns (uint256);
    function totalShares() external view returns (uint256);
    function slippage() external view returns (uint256);
    function rate(uint256) external view returns (uint256);
    function mint(address, uint256, bytes calldata) external returns (uint256);
    function burn(address, uint256, bytes calldata) external returns (uint256);
    function exit(address str) external;
    function move(address old) external;
}

