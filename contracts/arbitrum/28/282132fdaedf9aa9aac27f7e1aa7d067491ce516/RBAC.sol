// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./AccessControlUpgradeable.sol";
import "./UUPSUpgradeable.sol";

contract RBAC is AccessControlUpgradeable, UUPSUpgradeable {

    function __RBAC_init() internal onlyInitializing {
        __AccessControl_init();
        __UUPSUpgradeable_init();
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

    function _authorizeUpgrade(address) internal override onlyOwner {}

    uint256[50] private __gap;
}

