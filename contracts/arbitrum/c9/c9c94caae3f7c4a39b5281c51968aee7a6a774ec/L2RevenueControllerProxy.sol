//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./TransparentUpgradeableProxy.sol";

contract L2RevenueControllerProxy is TransparentUpgradeableProxy {
    constructor(address _logic, address _proxyAdmin)
        TransparentUpgradeableProxy(_logic, _proxyAdmin, "")
    {}
}
