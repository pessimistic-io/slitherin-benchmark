// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";

abstract contract UpgradeableGovernable is AccessControlUpgradeable {
    bytes32 public constant GOVERNOR = bytes32("GOVERNOR");

    function __Governable_init(address _governor) internal onlyInitializing {
        __AccessControl_init();
        _grantRole(GOVERNOR, _governor);
    }

    modifier onlyGovernor() {
        _onlyGovernor();
        _;
    }

    function updateGovernor(address _newGovernor) external virtual onlyGovernor {
        _revokeRole(GOVERNOR, msg.sender);
        _grantRole(GOVERNOR, _newGovernor);

        emit GovernorUpdated(msg.sender, _newGovernor);
    }

    function _onlyGovernor() private view {
        if (!hasRole(GOVERNOR, msg.sender)) {
            revert CallerIsNotGovernor();
        }
    }

    event GovernorUpdated(address _oldGovernor, address _newGovernor);

    error CallerIsNotGovernor();
}

