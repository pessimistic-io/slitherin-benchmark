// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {TransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";

contract L2Proxy is TransparentUpgradeableProxy {

    constructor(
        address _logic,
        address _admin,
        bytes memory _data
    ) payable TransparentUpgradeableProxy(_logic, _admin, _data) {}

}

