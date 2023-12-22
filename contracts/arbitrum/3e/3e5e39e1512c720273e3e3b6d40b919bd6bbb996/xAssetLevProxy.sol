//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.4;

import "./BeaconProxy.sol";

contract xAssetLevProxy is BeaconProxy {
    constructor(address beacon) BeaconProxy(beacon, "") {}
}

