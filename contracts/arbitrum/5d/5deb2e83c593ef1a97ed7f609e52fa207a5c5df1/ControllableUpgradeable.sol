// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AccessControl } from "./AccessControl.sol";

import { Constants } from "./Constants.sol";
import { Controller } from "./Controller.sol";
import { Initializable } from "./Initializable.sol";

error notGovernance();
error notKeeper();
error notMultisig();
error notLiquidator();

// Contains logic to fetch access control info from the Controller.
contract ControllableUpgradeable is Initializable {
    address public controller;

    function __Controllable_init(address _controller) internal initializer {
        controller = _controller;
    }

    // Revert if msg.sender is not the Controller's Governor
    modifier onlyGovernor() {
        if (!AccessControl(controller).hasRole(Constants.DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert notGovernance();
        }
        _;
    }

    // Revert if msg.sender is not registered as a keeper in the Controller
    modifier onlyKeeper() {
        if (!AccessControl(controller).hasRole(Constants.KEEPER_ROLE, msg.sender)) {
            revert notKeeper();
        }
        _;
    }

    modifier onlyMultisig() {
        if (!AccessControl(controller).hasRole(Constants.MULTISIG_ROLE, msg.sender)) {
            revert notMultisig();
        }
        _;
    }

    modifier onlyLiquidator() {
        if (!AccessControl(controller).hasRole(Constants.LIQUIDATOR_ROLE, msg.sender)) {
            revert notLiquidator();
        }
        _;
    }

    uint256[49] private __gap;
}

