// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IAccessControl.sol";
import "./IDeploymentManager.sol";


abstract contract UmamiAccessControlled {
    event ManagerUpdated(IDeploymentManager indexed authority);

    string UNAUTHORIZED = "UNAUTHORIZED"; // save gas

    IDeploymentManager public deploymentManager;

    constructor(IDeploymentManager manager) {
        deploymentManager = manager;
        emit ManagerUpdated(manager);
    }

    modifier onlyDepositWithdrawer() {
        bytes32 role = deploymentManager.getDepositWithdrawRole();
        require(deploymentManager.hasRole(role, msg.sender), UNAUTHORIZED);
        _;
    }

    modifier onlyManager() {
        bytes32 role = deploymentManager.getManageRole();
        require(deploymentManager.hasRole(role, msg.sender), UNAUTHORIZED);
        _;
    }

    function setManager(IDeploymentManager manager) external onlyManager {
        deploymentManager = manager;
        emit ManagerUpdated(manager);
    }
}
