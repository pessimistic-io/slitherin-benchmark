// SPDX-License-Identifier: BUSDL-1.1
pragma solidity 0.6.11;

import {Ownable} from "./common_Imports.sol";
import {TransparentUpgradeableProxy} from "./proxy_Imports.sol";

contract ProxyFactoryV2 {
    function create(
        address logic,
        address proxyAdmin,
        bytes memory initData
    ) public returns (address) {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(logic, proxyAdmin, initData);
        return address(proxy);
    }

    function createAndTransfer(
        address logic,
        address proxyAdmin,
        bytes memory initData,
        address owner
    ) public returns (address) {
        address proxy = create(logic, proxyAdmin, initData);
        Ownable(proxy).transferOwnership(owner);
        return proxy;
    }
}

