// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.21;

/**
 * @title Roles library
 * @author Pulsar Finance
 * @notice Roles Definition for Access Control Flow
 **/

library Roles {
    bytes32 public constant CONTROLLER = keccak256("CONTROLLER");
    bytes32 public constant STRATEGY_WORKER = keccak256("STRATEGY_WORKER");
    bytes32 public constant CONTROLLER_CALLER = keccak256("CONTROLLER_CALLER");
}

