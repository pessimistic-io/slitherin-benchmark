// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governable} from "./Governable.sol";

abstract contract Operable is Governable {
    bytes32 public constant OPERATOR = bytes32("OPERATOR");

    modifier onlyOperator() {
        if (!hasRole(OPERATOR, msg.sender)) {
            revert CallerIsNotOperator();
        }

        _;
    }

    modifier onlyGovernorOrOperator() {
        if (!(hasRole(GOVERNOR, msg.sender) || hasRole(OPERATOR, msg.sender))) {
            revert CallerIsNotAllowed();
        }

        _;
    }

    function addOperator(address _newOperator) external onlyGovernor {
        _grantRole(OPERATOR, _newOperator);

        emit OperatorAdded(_newOperator);
    }

    function removeOperator(address _operator) external onlyGovernor {
        _revokeRole(OPERATOR, _operator);

        emit OperatorRemoved(_operator);
    }

    event OperatorAdded(address _newOperator);
    event OperatorRemoved(address _operator);

    error CallerIsNotOperator();
    error CallerIsNotAllowed();
}

