// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AccessControl } from "./AccessControl.sol";
import { Constants } from "./Constants.sol";
import { Controller } from "./Controller.sol";

error notGovernance();
error notKeeper();
error notMultisig();
error notLiquidator();
error notVault();

// Contains logic to fetch access control info from the Controller.
contract Controllable {
    address public immutable controller;

    constructor(address _controller) {
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

    modifier onlyVault() {
        if (!AccessControl(controller).hasRole(Constants.VAULT_ROLE, msg.sender)) {
            revert notVault();
        }
        _;
    }
}

