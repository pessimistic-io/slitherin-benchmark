// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

contract JiraFusion is TransparentUpgradeableProxy {
    constructor(address logic_, address admin_, bytes memory data_) 
        TransparentUpgradeableProxy(logic_, admin_, data_) {
    }
}
