// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {Governable} from "./Governable.sol";

abstract contract OperableInitializable is Governable {
    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Operator role
     */
    bytes32 public constant OPERATOR = bytes32("OPERATOR");

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Only msg.sender with OPERATOR role can call the function.
     */
    modifier onlyOperator() {
        if (!hasRole(OPERATOR, msg.sender)) {
            revert CallerIsNotOperator();
        }

        _;
    }

    /**
     * @notice Only msg.sender with OPERATOR or GOVERNOR role can call the function.
     */
    modifier onlyGovernorOrOperator() {
        if (!(hasRole(GOVERNOR, msg.sender) || hasRole(OPERATOR, msg.sender))) {
            revert CallerIsNotAllowed();
        }

        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                ONLY GOVERNOR                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Grant Operator role to _newOperator.
     */
    function addOperator(address _newOperator) external onlyGovernor {
        _grantRole(OPERATOR, _newOperator);

        emit OperatorAdded(_newOperator);
    }

    /**
     * @notice Remove Operator role from _operator.
     */
    function removeOperator(address _operator) external onlyGovernor {
        _revokeRole(OPERATOR, _operator);

        emit OperatorRemoved(_operator);
    }

    event OperatorAdded(address _newOperator);
    event OperatorRemoved(address _operator);

    error CallerIsNotOperator();
    error CallerIsNotAllowed();
}

