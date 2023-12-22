// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {AccessControl} from "./AccessControl.sol";
import {Governable} from "./Governable.sol";

abstract contract Keepable is Governable {
    bytes32 public constant KEEPER = bytes32("KEEPER");

    modifier onlyKeeper() {
        if (!hasRole(KEEPER, msg.sender)) {
            revert CallerIsNotKeeper();
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

    error CallerIsNotKeeper();
}

