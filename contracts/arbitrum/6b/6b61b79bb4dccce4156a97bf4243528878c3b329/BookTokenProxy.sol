// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

contract BookTokenProxy is TransparentUpgradeableProxy {
    constructor (
        address logic,
        address admin_
    ) TransparentUpgradeableProxy(logic, admin_, "") {}
}


