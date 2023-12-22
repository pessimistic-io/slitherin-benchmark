// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {TransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";

/// @title    GSWForwarderProxy
/// @notice   Default ERC1967Proxy for GSWForwarder
contract GSWForwarderProxy is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) payable TransparentUpgradeableProxy(_logic, admin_, _data) {}
}

