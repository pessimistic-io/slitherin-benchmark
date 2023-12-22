// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IAccessControl.sol";

interface IDeploymentManager is IAccessControl {
    function getRewardDestination() external view returns (address);
    function getManageRole() external view returns (bytes32);
    function getDepositWithdrawRole() external view returns (bytes32);
    function getAutomationRole() external view returns (bytes32);
}
