// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

contract OwnableUpgradeableSafe is OwnableUpgradeable {
    function renounceOwnership() public view override onlyOwner {
        revert("OS_NR"); // not able to renounce
    }
}

