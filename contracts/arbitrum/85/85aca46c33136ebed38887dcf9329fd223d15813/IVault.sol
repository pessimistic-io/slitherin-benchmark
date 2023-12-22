/**
 * Interface for the vault
 */

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IVault {
    function approveDaddyDiamond(address token, uint256 amt) external;
}

