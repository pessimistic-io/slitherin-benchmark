// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

interface IPolyStrategy {
    // Deposit amount of tokens for 'caller' to address 'to'
    function deposit(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 pidMonopoly
    ) external;

    // Transfer tokens from strategy for 'caller' to address 'to'
    function withdraw(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 withdrawalFeeBP,
        uint256 pidMonopoly
    ) external;

    function inCaseTokensGetStuck(
        IERC20 token,
        address to,
        uint256 amount
    ) external;

    function setAllowances(uint256 pid) external;

    function revokeAllowance(address token, address spender, uint256 pid) external;

    function migrate(address newStrategy, uint256 pid) external;

    function onMigration(uint256 pid) external;

    function pendingTokens(
        uint256 pid,
        address user,
        uint256 amount
    ) external view returns (address[] memory, uint256[] memory);

    function transferOwnership(address newOwner) external;

    function setPerformanceFeeBips(uint256 newPerformanceFeeBips) external;

    function emergencyWithdraw(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 withdrawalFeeBP,
        uint256 pidMonopoly
    ) external;
}

