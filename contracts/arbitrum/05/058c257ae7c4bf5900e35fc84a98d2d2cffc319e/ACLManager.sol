// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Ownable.sol";
import "./IACLManager.sol";

contract ACLManager is IACLManager, AccessControl, Ownable {

    bytes32 public constant EMERGENCY_ADMIN_ROLE = keccak256('EMERGENCY_ADMIN');

    bytes32 public constant GOVERNANCE_ROLE = keccak256('GOVERNANCE');

    bytes32 public constant OPERATOR = keccak256('OPERATOR');

    bytes32 public constant BIDS = keccak256('BIDS');

    constructor() Ownable() {
        _setupRole(DEFAULT_ADMIN_ROLE, owner());
    }
    
    function addEmergencyAdmin(address _admin) external override {
        grantRole(EMERGENCY_ADMIN_ROLE, _admin);
    }

    function isEmergencyAdmin(address _admin) external view override returns (bool) {
        return hasRole(EMERGENCY_ADMIN_ROLE, _admin);
    }

    function removeEmergencyAdmin(address _admin) external override {
        revokeRole(EMERGENCY_ADMIN_ROLE, _admin);
    }

    function addGovernance(address _admin) external override {
        grantRole(GOVERNANCE_ROLE, _admin);
    }

    function isGovernance(address _admin) external view override returns (bool) {
        return hasRole(GOVERNANCE_ROLE, _admin);
    }

    function removeGovernance(address _admin) external override {
        revokeRole(GOVERNANCE_ROLE, _admin);
    }

    function addOperator(address _address) external override {
        grantRole(OPERATOR, _address);
    }

    function isOperator(address _address) external view override returns (bool) {
        return hasRole(OPERATOR, _address);
    }

    function removeOperator(address _address) external override {
        revokeRole(OPERATOR, _address);
    }

    function addBidsContract(address _bids) external {
        grantRole(BIDS, _bids);
    }

    function isBidsContract(address _bids) external view returns (bool) {
        return hasRole(BIDS, _bids);
    }

    function removeBidsContract(address _bids) external {
        revokeRole(BIDS, _bids);
    }
}

