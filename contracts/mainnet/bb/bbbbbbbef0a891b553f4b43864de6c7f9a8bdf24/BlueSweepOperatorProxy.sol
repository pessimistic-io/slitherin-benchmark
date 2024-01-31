// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

contract BlueSweepOperatorProxy is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) payable TransparentUpgradeableProxy(_logic, admin_, _data) {
        
    }
}

