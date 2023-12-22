// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWhitelist {
    event TokenAdded(address indexed token, uint256 index);
    event TokenRemoved(address indexed token, uint256 index);

    function tokenCount() external view returns (uint256);
    function getTokenIndex(address token) external view returns (uint256, bool);
    function addToken(address token) external;
    function removeToken(address token) external;
}
