// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./TransparentUpgradeableProxy.sol";

contract ProxyPermanentStorage is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address _admin,
        bytes memory _data
    ) payable TransparentUpgradeableProxy(_logic, _admin, _data) {}
}

