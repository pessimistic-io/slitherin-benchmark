// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.16;

import { LibDiamond } from "./LibDiamond.sol";
import { AppStorage, LibAppStorage } from "./LibAppStorage.sol";
import { Ownable } from "./Ownable.sol";

contract PauseFacet is Ownable {
    AppStorage internal s;

    event Pause(uint256 timestamp);
    event Unpause(uint256 timestamp);

    function pause() external onlyOwner {
        require(!s.paused, "Pause: already paused.");
        s.paused = true;
        s.pausedAt = uint128(block.timestamp);
        emit Pause(block.timestamp);
    }

    function unpause() external onlyOwner {
        require(s.paused, "Pause: not paused.");
        s.paused = false;
        emit Unpause(block.timestamp);
    }
}

