// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableUDS} from "./OwnableUDS.sol";
import {UUPSUpgrade} from "./UUPSUpgrade.sol";
import {AccessControlUDS} from "./AccessControlUDS.sol";
import {FxERC20RelayRoot} from "./FxERC20RelayRoot.sol";

/// @title Gouda Root Relay
/// @notice Flexible ERC20 Token Relay
/// @author phaze (https://github.com/0xPhaze/fx-contracts)
contract GoudaRootRelay is UUPSUpgrade, OwnableUDS, FxERC20RelayRoot {
    constructor(
        address gouda,
        address checkpointManager,
        address fxRoot
    ) FxERC20RelayRoot(gouda, checkpointManager, fxRoot) {
        __Ownable_init();
    }

    /* ------------- owner ------------- */

    function _authorizeUpgrade() internal override onlyOwner {}

    function _authorizeTunnelController() internal override onlyOwner {}
}

