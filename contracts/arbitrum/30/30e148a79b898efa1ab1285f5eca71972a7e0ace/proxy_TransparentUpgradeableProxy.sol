// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "./proxy_TransparentUpgradeableProxy.sol";

contract SumerProxy is TransparentUpgradeableProxy {
    constructor(
        address logic,
        address admin_,
        bytes memory data
    ) payable TransparentUpgradeableProxy(logic, admin_, data) {}
}

