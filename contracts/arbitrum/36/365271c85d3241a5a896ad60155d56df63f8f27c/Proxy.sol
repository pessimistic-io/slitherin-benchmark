// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./TransparentUpgradeableProxy.sol";

contract ExtremeDogeGenesisProxy is TransparentUpgradeableProxy {
    constructor(address _logic, address admin_)
        TransparentUpgradeableProxy(_logic, admin_, "")
    {}
}

