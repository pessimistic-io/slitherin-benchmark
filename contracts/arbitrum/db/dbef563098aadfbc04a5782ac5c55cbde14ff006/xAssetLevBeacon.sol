//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.4;

import "./UpgradeableBeacon.sol";

contract xAssetLevBeacon is UpgradeableBeacon {
    constructor(address _implementation) UpgradeableBeacon(_implementation) {}
}

