// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { OwnableUpgradeableSafe } from "./OwnableUpgradeableSafe.sol";

contract OwnerPausableUpgradeSafe is OwnableUpgradeableSafe, PausableUpgradeable {
    function __OwnerPausable_init() internal initializer {
        __Ownable_init();
        __Pausable_init();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    uint256[50] private __gap;
}

