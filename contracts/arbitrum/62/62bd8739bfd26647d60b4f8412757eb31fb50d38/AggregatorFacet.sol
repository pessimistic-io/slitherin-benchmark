// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";
import {LibGuard} from "./LibGuard.sol";
import {AppStorage} from "./LibMagpieAggregator.sol";
import {LibPauser} from "./LibPauser.sol";
import {LibRouter} from "./LibRouter.sol";
import {IAggregator} from "./IAggregator.sol";
import {LibAggregator, SwapArgs, SwapInArgs, SwapOutArgs} from "./LibAggregator.sol";

contract AggregatorFacet is IAggregator {
    AppStorage internal s;

    function updateWeth(address weth) external override {
        LibDiamond.enforceIsContractOwner();
        LibAggregator.updateWeth(weth);
    }

    function updateMagpieRouterAddress(address magpieRouterAddress) external override {
        LibDiamond.enforceIsContractOwner();
        LibAggregator.updateMagpieRouterAddress(magpieRouterAddress);
    }

    function updateNetworkId(uint16 networkId) external override {
        LibDiamond.enforceIsContractOwner();
        LibAggregator.updateNetworkId(networkId);
    }

    function addMagpieAggregatorAddresses(
        uint16[] calldata networkIds,
        bytes32[] calldata magpieAggregatorAddresses
    ) external override {
        LibDiamond.enforceIsContractOwner();
        LibAggregator.addMagpieAggregatorAddresses(networkIds, magpieAggregatorAddresses);
    }

    function estimateSwapGas(
        SwapArgs calldata swapArgs
    ) external payable override returns (uint256 amountOut, uint256[] memory gasUsed) {
        LibRouter.enforceDeadline(swapArgs.deadline);
        LibPauser.enforceIsNotPaused();
        LibGuard.enforcePreGuard();
        (amountOut, gasUsed) = LibAggregator.swap(swapArgs, true);
        LibGuard.enforcePostGuard();
    }

    function swap(SwapArgs calldata swapArgs) external payable override returns (uint256 amountOut) {
        LibRouter.enforceDeadline(swapArgs.deadline);
        LibPauser.enforceIsNotPaused();
        LibGuard.enforcePreGuard();
        (amountOut, ) = LibAggregator.swap(swapArgs, false);
        LibGuard.enforcePostGuard();
    }

    function swapIn(SwapInArgs calldata swapInArgs) external payable override returns (uint256 amountOut) {
        LibRouter.enforceDeadline(swapInArgs.swapArgs.deadline);
        LibPauser.enforceIsNotPaused();
        LibGuard.enforcePreGuard();
        amountOut = LibAggregator.swapIn(swapInArgs);
        LibGuard.enforcePostGuard();
    }

    function swapOut(SwapOutArgs calldata swapOutArgs) external override returns (uint256 amountOut) {
        LibRouter.enforceDeadline(swapOutArgs.swapArgs.deadline);
        LibPauser.enforceIsNotPaused();
        LibGuard.enforcePreGuard();
        amountOut = LibAggregator.swapOut(swapOutArgs);
        LibGuard.enforcePostGuard();
    }

    function withdraw(address assetAddress) external override {
        LibPauser.enforceIsNotPaused();
        LibAggregator.withdraw(assetAddress);
    }

    function getDeposit(address assetAddress) external view override returns (uint256) {
        return LibAggregator.getDeposit(assetAddress);
    }

    function getDepositByUser(address assetAddress, address senderAddress) external view override returns (uint256) {
        return LibAggregator.getDepositByUser(assetAddress, senderAddress);
    }

    function isTransferKeyUsed(
        uint16 networkId,
        bytes32 senderAddress,
        uint64 swapSequence
    ) external view override returns (bool) {
        return LibAggregator.isTransferKeyUsed(networkId, senderAddress, swapSequence);
    }
}

