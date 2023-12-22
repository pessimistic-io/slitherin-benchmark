// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";

/// @title    AvoVersionsRegistryProxy
/// @notice   Default ERC1967Proxy for AvoVersionsRegistryProxy
contract AvoVersionsRegistryProxy is TransparentUpgradeableProxy {
    constructor(
        address logic_,
        address admin_,
        bytes memory data_
    ) payable TransparentUpgradeableProxy(logic_, admin_, data_) {}
}

