/**
 * Interface for the TokenStasher
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ITokenStash {
    function unstashTokens(address tokenAddress, uint256 amount) external;
    function stashTokens(address tokenAddress, uint256 amount) external;
}

