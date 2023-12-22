// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {AccessControl} from "./AccessControl.sol";
import {Initializable} from "./utils_Initializable.sol";

abstract contract Governable is Initializable, AccessControl {
    /**
     * @notice Governor role
     */
    bytes32 public constant GOVERNOR = bytes32("GOVERNOR");

    /**
     * @notice Initialize Governable contract.
     */
    function __Governable_init(address _governor) internal onlyInitializing {
        _grantRole(GOVERNOR, _governor);
    }

    /**
     * @notice Modifier if msg.sender has not Governor role revert.
     */
    modifier onlyGovernor() {
        _onlyGovernor();
        _;
    }

    /**
     * @notice Update Governor Role
     */
    function updateGovernor(address _newGovernor) external onlyGovernor {
        _revokeRole(GOVERNOR, msg.sender);
        _grantRole(GOVERNOR, _newGovernor);

        emit GovernorUpdated(msg.sender, _newGovernor);
    }

    /**
     * @notice If msg.sender has not Governor role revert.
     */
    function _onlyGovernor() private view {
        if (!hasRole(GOVERNOR, msg.sender)) {
            revert CallerIsNotGovernor();
        }
    }

    event GovernorUpdated(address _oldGovernor, address _newGovernor);

    error CallerIsNotGovernor();
}

