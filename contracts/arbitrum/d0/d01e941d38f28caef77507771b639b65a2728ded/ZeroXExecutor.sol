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

        uint unitPrice = (amountReceived * Constants.VAULT_PRECISION) /
            sellAmount;

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
}

