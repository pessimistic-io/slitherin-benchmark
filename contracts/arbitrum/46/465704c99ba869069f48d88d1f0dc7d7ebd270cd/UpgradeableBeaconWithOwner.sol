//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./UpgradeableBeacon.sol";

contract UpgradeableBeaconWithOwner is UpgradeableBeacon {
    constructor(address implementation, address owner) UpgradeableBeacon(implementation) {
        _transferOwnership(owner);
    }
}

