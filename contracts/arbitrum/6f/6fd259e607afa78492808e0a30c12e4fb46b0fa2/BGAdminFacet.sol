// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { DiamondOwnable } from "./DiamondOwnable.sol";
import { DiamondAccessControl } from "./DiamondAccessControl.sol";

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

contract BGAdminFacet is WithModifiers, DiamondAccessControl {
    event PauseStateChanged(bool paused);

    /**
     * @dev Pause the contract
     */
    function pause() external onlyGuardian notPaused {
        gs().paused = true;
        emit PauseStateChanged(true);
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyGuardian {
        if (!gs().paused) revert Errors.GameAlreadyUnPaused();
        gs().paused = false;
        emit PauseStateChanged(false);
    }

    /**
     * @dev Return the paused state
     */
    function isPaused() external view returns (bool) {
        return gs().paused;
    }
}

