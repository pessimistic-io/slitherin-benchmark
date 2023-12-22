// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

/**
 * @title IUpdatable
 */
interface IUpdatable {
    /* ========== CORE FUNCTIONS ========== */
    function update(bytes calldata data) external;
}

