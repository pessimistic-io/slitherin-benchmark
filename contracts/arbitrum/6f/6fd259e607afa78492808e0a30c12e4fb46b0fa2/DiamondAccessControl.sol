// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC173 } from "./IERC173.sol";
import { DiamondOwnable } from "./DiamondOwnable.sol";
import { WithStorage } from "./LibStorage.sol";

contract DiamondAccessControl is WithStorage, DiamondOwnable {
    function setGuardian(address account, bool state) external onlyOwner {
        gs().guardian[account] = state;
    }

    function isGuardian(address account) external view returns (bool) {
        return gs().guardian[account];
    }
}

