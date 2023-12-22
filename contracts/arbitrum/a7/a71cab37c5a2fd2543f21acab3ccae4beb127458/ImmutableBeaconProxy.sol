//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./UpgradeableBeacon.sol";
import "./Proxy.sol";

contract ImmutableBeaconProxy is Proxy {
    UpgradeableBeacon public immutable __beacon;

    constructor(UpgradeableBeacon beacon) {
        __beacon = beacon;
    }

    function _implementation() internal view override returns (address) {
        return __beacon.implementation();
    }
}

