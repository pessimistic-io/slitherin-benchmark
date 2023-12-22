// SPDX-License-Identifier: BUSL-1.1
// Last deployed from commit: b75e073cf23a3eb181f55a89a800ef040b7ba456;
pragma solidity 0.8.17;

import "./TransparentUpgradeableProxy.sol";

contract WethPoolTUP is TransparentUpgradeableProxy {
    constructor(address _logic, address admin_, bytes memory _data) TransparentUpgradeableProxy(_logic, admin_, _data) {}
}

