// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { ProxyAdmin } from "./ProxyAdmin.sol";

/// @dev This is an auxiliary contract meant to be assigned as the admin of a {TransparentUpgradeableProxy}. For an
/// explanation of why you would want to use this see the documentation for {TransparentUpgradeableProxy}.
contract AvoAdmin is ProxyAdmin {
    constructor(address _owner) {
        _transferOwnership(_owner);
    }
}

