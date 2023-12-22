// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";
import {AppStorage} from "./LibMagpieAggregator.sol";
import {IPauser} from "./IPauser.sol";
import {LibPauser} from "./LibPauser.sol";

contract PauserFacet is IPauser {
    AppStorage internal s;

    function pause() external override {
        LibDiamond.enforceIsContractOwner();
        LibPauser.pause();
    }

    function unpause() external override {
        LibDiamond.enforceIsContractOwner();
        LibPauser.unpause();
    }
}

