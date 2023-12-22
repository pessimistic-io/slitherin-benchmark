// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";

contract StablecoinProxy is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address _proxyAdmin,
        address _admin
    ) TransparentUpgradeableProxy(_logic, _proxyAdmin, abi.encodeWithSignature("initialize(address)", _admin)) {}
}

