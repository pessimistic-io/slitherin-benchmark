// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

contract ControllableAbs is OwnableUpgradeable {
    // address -> is controller
    mapping(address => bool) public controllers;

    event ControllerChanged(address indexed controller, bool enabled);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Controllable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function setController(address controller, bool enabled) public onlyOwner {
        controllers[controller] = enabled;
        emit ControllerChanged(controller, enabled);
    }

    modifier onlyController() {
        require(
            controllers[msg.sender],
            "Controllable: Caller is not a controller"
        );
        _;
    }
}
