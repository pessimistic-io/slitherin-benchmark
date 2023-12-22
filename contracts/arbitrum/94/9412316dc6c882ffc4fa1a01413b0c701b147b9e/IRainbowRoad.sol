// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IRainbowRoad {
    function team() external view returns (address);
    function teamRate() external view returns (uint256);
    function feeManagers(address feeManager) external view returns (bool);
    function blockedTokens(address tokenAddress) external view returns (bool);
    function tokens(string calldata tokenSymbol) external view returns (address);
    function receiveAction(string calldata action, address to, bytes calldata payload) external;
    function sendAction(string calldata action, address from, bytes calldata payload) external;
}
