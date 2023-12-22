/**
 * Interface for the TokenStasher
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IGasManager {
    function stashOperationGas(uint256 operationIndex) external payable;
}

