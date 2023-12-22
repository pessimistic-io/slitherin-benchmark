// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";
import {Amm, AppStorage} from "./LibMagpieRouter.sol";
import {IRouter} from "./IRouter.sol";
import {LibRouter, SwapArgs} from "./LibRouter.sol";

contract RouterFacet is IRouter {
    AppStorage internal s;

    function updateWeth(address weth) external override {
        LibDiamond.enforceIsContractOwner();
        LibRouter.updateWeth(weth);
    }

    function updateMagpieAggregatorAddress(address magpieAggregatorAddress) external override {
        LibDiamond.enforceIsContractOwner();
        LibRouter.updateMagpieAggregatorAddress(magpieAggregatorAddress);
    }

    function addAmm(uint16 ammId, Amm calldata amm) external override {
        LibDiamond.enforceIsContractOwner();
        LibRouter.addAmm(ammId, amm);
    }

    function removeAmm(uint16 ammId) external override {
        LibDiamond.enforceIsContractOwner();
        LibRouter.removeAmm(ammId);
    }

    function addAmms(uint16[] calldata ammIds, Amm[] calldata amms) external override {
        LibDiamond.enforceIsContractOwner();
        LibRouter.addAmms(ammIds, amms);
    }

    function updateCurveSettings(address addressProvider) external override {
        LibDiamond.enforceIsContractOwner();
        LibRouter.updateCurveSettings(addressProvider);
    }

    function swap(
        SwapArgs calldata swapArgs,
        bool estimateGas
    ) external payable override returns (uint256 amountOut, uint256[] memory gasUsed) {
        LibRouter.enforceIsMagpieAggregator();
        LibRouter.enforceDeadline(swapArgs.deadline);
        (amountOut, gasUsed) = LibRouter.swap(swapArgs, estimateGas);
    }
}

