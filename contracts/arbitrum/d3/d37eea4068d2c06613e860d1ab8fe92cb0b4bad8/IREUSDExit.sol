// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./IERC20Full.sol";

interface IREUSDExit
{
    error ZeroAmount();

    event QueueExit(address user, uint256 amount);
    event Exit(address user, uint256 amount);

    struct QueuedExitInfo
    {
        address user;
        uint256 amount;
    }

    function isREUSDExit() external view returns (bool);
    function queuedExitAt(uint256 index) external view returns (QueuedExitInfo memory);
    function queuedExitStart() external view returns (uint256);
    function queuedExitEnd() external view returns (uint256);
    function totalQueued() external view returns (uint256);

    function queueExitFor(address receiver, uint256 amount) external;
    function queueExit(uint256 amount) external;
    function queueExitPermit(uint256 amount, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function fund(IERC20Full token, uint256 maxTokenAmount) external;
    function fundPermit(IERC20Full token, uint256 maxTokenAmount, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}
