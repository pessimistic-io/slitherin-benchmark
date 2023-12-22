// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "./PeripheryUpgradeable.sol";

contract PeripheryImmutableStateTest is Initializable, PeripheryUpgradeable {
    /// @dev prevents implementation from being initialized later
    constructor() initializer() {}

    /// @dev not checking initializer() just for testing
    function initialize(address _factory, address _WETH9) external {
        factory = _factory;
        WETH9 = _WETH9;
    }
}

