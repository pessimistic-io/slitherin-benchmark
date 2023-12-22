// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity 0.8.16;

import {ProxyAdmin} from "./ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";

// @note This file is only for facilitating contract imports for brownie script

contract PA is ProxyAdmin {

}

contract TUP is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) payable TransparentUpgradeableProxy(_logic, admin_, _data) {}
}

