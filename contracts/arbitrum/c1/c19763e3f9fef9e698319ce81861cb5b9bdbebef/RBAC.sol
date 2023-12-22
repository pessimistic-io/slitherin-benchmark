// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./AccessControl.sol";

contract RBAC is AccessControl {
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    bytes32 public constant REBALANCE_PROVIDER_ROLE =
        0x524542414c414e43455f50524f56494445525f524f4c45000000000000000000;

    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not the owner");
        _;
    }

    modifier onlyRebalanceProvider() {
        require(hasRole(REBALANCE_PROVIDER_ROLE, msg.sender), "Caller is not a rabalance provider");
        _;
    }
}

