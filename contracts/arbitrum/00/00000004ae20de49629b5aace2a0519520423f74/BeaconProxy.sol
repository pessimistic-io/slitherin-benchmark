// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IBeacon.sol";
import "./Proxy.sol";

contract BeaconProxy is Proxy {
    IBeacon constant beacon =
        IBeacon(0x0000000eaAfD44b5123073D71317c2A73e38228d);

    function _implementation() internal view override returns (address) {
        return beacon.implementation();
    }
}

