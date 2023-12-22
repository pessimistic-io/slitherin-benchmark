// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";

import {IV3SwapRouter} from "./IV3SwapRouter.sol";
import {AaveLogicLib} from "./AaveLogicLib.sol";
import {BaseContract, Constants} from "./BaseContract.sol";

import {IAaveActionLogic} from "./IAaveActionLogic.sol";

/// @title AaveActionLogic
/// @notice A contract containing the logic for working with the aave protocol
contract AaveActionLogic is IAaveActionLogic, BaseContract {
    IPoolAddressesProvider private immutable poolAddressesProvider;
    IV3SwapRouter private immutable uniswapRouter;

    constructor(
        IPoolAddressesProvider _poolAddressesProvider,
        IV3SwapRouter _uniswapRouter
    ) {
        poolAddressesProvider = _poolAddressesProvider;
        uniswapRouter = _uniswapRouter;
    }

    // =========================
    // Main Functions
    // =========================

    /// @inheritdoc IAaveActionLogic
    function borrowAaveAction(
        address borrowToken,
        uint256 amount
    ) external onlyVaultItself {
        AaveLogicLib.borrowAave(
            borrowToken,
            amount,
            address(this),
            poolAddressesProvider
        );
    }

    /// @inheritdoc IAaveActionLogic
    function supplyAaveAction(
        address supplyToken,
        uint256 amount
    ) external onlyVaultItself {
        AaveLogicLib.supplyAave(
            supplyToken,
            amount,
            address(this),
            poolAddressesProvider
        );
    }

    /// @inheritdoc IAaveActionLogic
    function repayAaveAction(
        address borrowToken,
        uint256 amount
    ) external onlyVaultItself {
        AaveLogicLib.repayAave(
            borrowToken,
            amount,
            address(this),
            poolAddressesProvider
        );
    }

    /// @inheritdoc IAaveActionLogic
    function withdrawAaveAction(
        address supplyToken,
        uint256 amount
    ) external onlyVaultItself {
        AaveLogicLib.withdrawAave(
            supplyToken,
            amount,
            address(this),
            poolAddressesProvider
        );
    }

    /// @inheritdoc IAaveActionLogic
    function emergencyRepayAave(
        address supplyToken,
        address borrowToken,
        uint24 poolFee
    ) external onlyVaultItself {
        AaveLogicLib.emergencyRepayAave(
            supplyToken,
            borrowToken,
            address(this),
            poolAddressesProvider,
            poolFee
        );
    }

    /// @inheritdoc IAaveActionLogic
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        return
            AaveLogicLib.executeOperation(
                asset,
                amount,
                premium,
                initiator,
                params,
                poolAddressesProvider,
                uniswapRouter
            );
    }
}

