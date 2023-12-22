// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {UpgradeableGovernable} from "./UpgradeableGovernable.sol";

abstract contract UpgradeableKeepable is UpgradeableGovernable {
    bytes32 public constant KEEPER = bytes32("KEEPER");

    modifier onlyKeeper() {
        if (!hasRole(KEEPER, msg.sender)) {
            revert CallerIsNotKeeper();
        }

        _;
    }

    modifier onlyGovernorOrKeeper() {
        if (!(hasRole(GOVERNOR, msg.sender) || hasRole(KEEPER, msg.sender))) {
            revert CallerIsNotAllowed();
        }

        _;
    }

    function addKeeper(address _newKeeper) external onlyGovernor {
        _grantRole(KEEPER, _newKeeper);

        emit KeeperAdded(_newKeeper);
    }

    function removeKeeper(address _operator) external onlyGovernor {
        _revokeRole(KEEPER, _operator);

        emit KeeperRemoved(_operator);
    }

    event KeeperAdded(address _newKeeper);
    event KeeperRemoved(address _operator);

    error CallerIsNotOperator();
    error CallerIsNotKeeper();
    error CallerIsNotAllowed();
}

