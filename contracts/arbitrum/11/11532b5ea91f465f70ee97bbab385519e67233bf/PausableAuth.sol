// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Auth, Authority} from "./Auth.sol";

import {Pausable} from "./Pausable.sol";

/// @notice Auth and Pausable.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/security/PausableAuth.sol)
abstract contract PausableAuth is Pausable, Auth {
    error PausableAuth__Paused();

    modifier onlyAuthorizedWhenPaused() {
        if (paused()) {
            if (!isAuthorized(msg.sender, msg.sig)) revert PausableAuth__Paused();
        }
        _;
    }

    function pause() external requiresAuth {
        _pause();
    }

    function unpause() external requiresAuth {
        _unpause();
    }
}

