// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { ProxyAdmin } from "./ProxyAdmin.sol";

abstract contract ProxyAdminDeployer {
    ProxyAdmin public proxyAdmin;

    function _deployProxyAdmin() internal returns (ProxyAdmin) {
        return new ProxyAdmin();
    }
}

