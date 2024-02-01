//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "./UUPSImplementation.sol";
import "./OwnableStorage.sol";

contract UpgradeModule is UUPSImplementation {
    function upgradeTo(address newImplementation) public override {
        OwnableStorage.onlyOwner();
        _upgradeTo(newImplementation);
    }
}

