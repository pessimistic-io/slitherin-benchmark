// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./IDeployment.sol";
import "./IUmamiAccessControlled.sol";


contract DeploymentManager is AccessControl {
    IDeployment[] public deployments;
    address public rewardDestination;

    bytes32 public constant MANAGE_ROLE = keccak256("MANAGE_ROLE");
    bytes32 public constant DEPOSIT_WITHDRAW_ROLE = keccak256("DEPOSIT_WITHDRAW_ROLE");
    bytes32 public constant AUTOMATION_ROLE = keccak256("AUTOMATION_ROLE");

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEPOSIT_WITHDRAW_ROLE, address(this));
        _grantRole(DEPOSIT_WITHDRAW_ROLE, msg.sender);
        _grantRole(MANAGE_ROLE, address(this));
        _grantRole(MANAGE_ROLE, msg.sender);
    }

    function harvestAll(bool dumpTokensForWeth) external onlyDepositWithdrawerOrAutomation {
        for (uint256 i = 0; i < deployments.length; i++) {
            deployments[i].harvest(dumpTokensForWeth);
        }
    }

    function withdrawAll(bool dumpTokensForWeth) external onlyDepositWithdrawer {
        for (uint256 i = 0; i < deployments.length; i++) {
            deployments[i].withdrawAll(dumpTokensForWeth);
        }
    }

    function compoundAll() external onlyDepositWithdrawer {
        for (uint256 i = 0; i < deployments.length; i++) {
            deployments[i].compound();
        }
    }

    function updateDeployments(IDeployment[] calldata _deployments) external onlyManager {
        deployments = _deployments;
    }

    function updateManagerForDeployments(IDeploymentManager manager) external onlyManager {
        for (uint256 i = 0; i < deployments.length; i++) {
            IUmamiAccessControlled(address(deployments[i])).setDeploymentManager(manager);
        }
    }

    function setRewardDestination(address destination) external onlyManager {
        rewardDestination = destination;
    }

    function getRewardDestination() external view returns (address) {
        return rewardDestination;
    }

    function getDepositWithdrawRole() external pure returns (bytes32) {
        return DEPOSIT_WITHDRAW_ROLE;
    }

    function getManageRole() external pure returns (bytes32) {
        return MANAGE_ROLE;
    }

    function getAutomationRole() external pure returns (bytes32) {
        return AUTOMATION_ROLE;
    }

    modifier onlyManager {
        require(hasRole(MANAGE_ROLE, msg.sender), "Not manager");
        _;
    }

    modifier onlyDepositWithdrawer {
        require(hasRole(DEPOSIT_WITHDRAW_ROLE, msg.sender), "Not deposit/withdrawer");
        _;
    }

    modifier onlyDepositWithdrawerOrAutomation {
        require(hasRole(DEPOSIT_WITHDRAW_ROLE, msg.sender) || 
            hasRole(AUTOMATION_ROLE, msg.sender), "Not deposit/withdrawer or automation");
        _;
    }
}
