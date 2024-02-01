// SPDX-License-Identifier: BUSDL-1.1
pragma solidity 0.6.11;

import {ProxyAdmin} from "./proxy_Imports.sol";

contract ProxyAdminFactory {
    function create() external returns (address) {
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        proxyAdmin.transferOwnership(msg.sender);
        return address(proxyAdmin);
    }
}

