// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./TransparentUpgradeableProxy.sol";

contract InstaConnectorsV2Proxy is TransparentUpgradeableProxy {
    constructor(address _logic, address admin_, bytes memory _data) public TransparentUpgradeableProxy(_logic, admin_, _data) {}
}
