// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

contract OwnerPausableUpgradeable is OwnableUpgradeable, PausableUpgradeable {
    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    // solhint-disable func-name-mixedcase
    function __OwnerPausable_init() internal onlyInitializing {
        __Ownable_init();
        __Pausable_init();
    }

    /**
     * @notice pauses trading
     * @dev only owner
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice resumes trading
     * @dev only owner
     */
    function unpause() public onlyOwner {
        _unpause();
    }
}

