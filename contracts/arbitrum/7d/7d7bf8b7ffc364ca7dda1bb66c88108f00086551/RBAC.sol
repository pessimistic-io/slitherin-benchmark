// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./AccessControl.sol";

contract RBAC is AccessControl {
    bool public whitelistDisabled;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(WHITELISTER_ROLE, msg.sender);
    }

    bytes32 public constant REBALANCE_PROVIDER_ROLE =
        0x524542414c414e43455f50524f56494445525f524f4c45000000000000000000;
    bytes32 public constant WHITELISTER_ROLE = 0x83f1255d648e40b6165de7ff5738d0dcec8910e0202ccdb1c5dc55ad7407d929;
    bytes32 public constant WHITELISTED_ROLE = 0x5efb91f1e806530b88ef3ea69875830a216ee5e51606217ae54501f71d53a6ce;

    function whitelistUser(address user) external onlyWhitelister {
        _grantRole(WHITELISTED_ROLE, user);
    }

    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not the owner");
        _;
    }

    modifier onlyRebalanceProvider() {
        require(hasRole(REBALANCE_PROVIDER_ROLE, msg.sender), "Caller is not a rabalance provider");
        _;
    }

    modifier onlyWhitelister() {
        require(hasRole(WHITELISTER_ROLE, msg.sender), "Caller is not a whitelister");
        _;
    }

    modifier onlyWhitelisted() {
        require(whitelistDisabled || hasRole(WHITELISTED_ROLE, msg.sender), "Caller is not whitelisted");
        _;
    }
}

