// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

contract FactorTransparentUpgradeableProxy is TransparentUpgradeableProxy {
    constructor(address logic, address admin, bytes memory data) TransparentUpgradeableProxy(logic, admin, data) {}
}

