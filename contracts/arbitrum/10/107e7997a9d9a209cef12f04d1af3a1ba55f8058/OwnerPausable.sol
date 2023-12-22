// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

contract OwnerPausableUpgradeable is OwnableUpgradeable, PausableUpgradeable {
    // solhint-disable func-name-mixedcase
    function __OwnerPausable_init() internal onlyInitializing {
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

