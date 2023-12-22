// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UpgradeableBeacon.sol";

contract Beacon is UpgradeableBeacon(msg.sender) {
    function _msgSender() internal view virtual override returns (address) {
        return tx.origin;
    }
}

