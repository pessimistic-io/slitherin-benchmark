// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";
import {Amm, AppStorage} from "./LibMagpieAggregator.sol";
import {IRouterManager} from "./IRouterManager.sol";
import {LibRouterManager} from "./LibRouterManager.sol";

contract RouterManagerFacet is IRouterManager {
    AppStorage internal s;

    function addAmm(uint16 ammId, Amm calldata amm) external override {
        LibDiamond.enforceIsContractOwner();
        LibRouterManager.addAmm(ammId, amm);
    }

    function removeAmm(uint16 ammId) external override {
        LibDiamond.enforceIsContractOwner();
        LibRouterManager.removeAmm(ammId);
    }

    function addAmms(uint16[] calldata ammIds, Amm[] calldata amms) external override {
        LibDiamond.enforceIsContractOwner();
        LibRouterManager.addAmms(ammIds, amms);
    }

    function updateCurveSettings(address addressProvider) external override {
        LibDiamond.enforceIsContractOwner();
        LibRouterManager.updateCurveSettings(addressProvider);
    }
}

