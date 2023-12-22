// contracts/MyPausable.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Pausable.sol";
import "./Dev.sol";

abstract contract MyPausable is Pausable, Dev {
    function setPaused(bool pause) external virtual onlyManger {
        if (pause) {
            _pause();
        } else {
            _unpause();
        }
    }
}

