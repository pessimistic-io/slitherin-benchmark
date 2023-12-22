// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.16;

import { AccessControlInternal } from "./AccessControlInternal.sol";
import { SystemStorage } from "./SystemStorage.sol";

contract PauseOwnable is AccessControlInternal {
    using SystemStorage for SystemStorage.Layout;

    event Pause(uint256 timestamp);
    event Unpause(uint256 timestamp);

    function pause() external onlyRole(ADMIN_ROLE) {
        SystemStorage.Layout storage s = SystemStorage.layout();

        require(!s.paused, "Pause: already paused.");
        s.paused = true;
        s.pausedAt = uint128(block.timestamp);
        emit Pause(block.timestamp);
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        SystemStorage.Layout storage s = SystemStorage.layout();

        require(s.paused, "Pause: not paused.");
        s.paused = false;
        emit Unpause(block.timestamp);
    }
}

