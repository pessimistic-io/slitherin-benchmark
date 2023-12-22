// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./TransparentUpgradeableProxy.sol";

contract CommonPlugProxy is TransparentUpgradeableProxy {
    constructor(
        address implementation,
        address admin_
    ) TransparentUpgradeableProxy(implementation, admin_, "") {}

    error OnlyProxyAdmin();

    function changeImpl(address impl) external {
        if (msg.sender != _getAdmin()) {
            revert OnlyProxyAdmin();
        }
        _upgradeTo(impl);
    }

    function changeAdmin(address admin_) external {
        if (msg.sender != _getAdmin()) {
            revert OnlyProxyAdmin();
        }

        _changeAdmin(admin_);
    }
}

