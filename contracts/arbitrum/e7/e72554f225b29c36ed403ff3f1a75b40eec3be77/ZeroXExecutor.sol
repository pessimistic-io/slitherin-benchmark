// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { I0xExchangeRouter } from "./I0xExchangeRouter.sol";
import { IExecutor, ExecutorIntegration, ExecutorAction } from "./IExecutor.sol";
import { VaultBaseExternal } from "./VaultBaseExternal.sol";
import { Registry } from "./Registry.sol";

import { Call } from "./Call.sol";
import { Constants } from "./Constants.sol";

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

import { IERC20Metadata } from "./IERC20Metadata.sol";

contract ZeroXExecutor is IExecutor {
    using SafeERC20 for IERC20;

    // This function is called by the vault via delegatecall cannot access state of this contract
    function swap(
        address sellTokenAddress,
        uint sellAmount,
        address buyTokenAddress,
        uint buyAmount,
        bytes memory zeroXSwapData
    ) external {
        Registry registry = VaultBaseExternal(address(this)).registry();
        require(
            registry.accountant().isDeprecated(buyTokenAddress) == false,
            'ZeroXExecutor: OutputToken is deprecated'
        );

        address _0xExchangeRouter = registry.zeroXExchangeRouter();

        IERC20(sellTokenAddress).approve(_0xExchangeRouter, sellAmount);

        uint balanceBefore = IERC20(buyTokenAddress).balanceOf(address(this));
        // Blindly execute the call to the 0x exchange router
        Call._call(_0xExchangeRouter, zeroXSwapData);

        uint balanceAfter = IERC20(buyTokenAddress).balanceOf(address(this));
        uint amountReceived = balanceAfter - balanceBefore;

        require(
            amountReceived >= buyAmount,
            'ZeroXExecutor: Not enough received'
        );

        uint unitPrice = _checkSingleSwapPriceImpact(
            registry,
            sellTokenAddress,
            sellAmount,
            buyTokenAddress,
            amountReceived
        );

        VaultBaseExternal(address(this)).updateActiveAsset(sellTokenAddress);
        VaultBaseExternal(address(this)).addActiveAsset(buyTokenAddress);
        registry.emitEvent();
        emit ExecutedManagerAction(
            ExecutorIntegration.ZeroX,
            ExecutorAction.Swap,
            sellTokenAddress,
            sellAmount,
            buyTokenAddress,
            amountReceived,
            unitPrice
        );
    }

    function _checkSingleSwapPriceImpact(
        Registry registry,
        address sellTokenAddress,
        uint sellAmount,
        address buyTokenAddress,
        uint buyAmount
    ) internal view returns (uint unitPrice) {
        uint priceImpactToleranceBasisPoints = registry
            .zeroXMaximumSingleSwapPriceImpactBips();

        (uint inputValue, ) = registry.accountant().assetValue(
            sellTokenAddress,
            sellAmount
        );

        (uint outputValue, ) = registry.accountant().assetValue(
            buyTokenAddress,
            buyAmount
        );

        unitPrice = (buyAmount * Constants.VAULT_PRECISION) / sellAmount;

        if (outputValue >= inputValue) {
            return unitPrice;
        }

        uint priceImpact = ((inputValue - outputValue) *
            Constants.BASIS_POINTS_DIVISOR) / inputValue;

        require(
            priceImpact <= priceImpactToleranceBasisPoints,
            'ZeroXExecutor: Price impact too high'
        );

        return unitPrice;
    }
}

