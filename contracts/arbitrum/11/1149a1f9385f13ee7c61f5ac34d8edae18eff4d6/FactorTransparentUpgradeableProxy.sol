// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

contract FactorTransparentUpgradeableProxy is TransparentUpgradeableProxy {
    constructor(
        address logic,
        address initialOwner,
        bytes memory data
    ) TransparentUpgradeableProxy(logic, initialOwner, data) {}
}

