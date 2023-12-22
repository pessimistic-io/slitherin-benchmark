// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPool} from "./IPool.sol";
import {IVariableDebtToken} from "./IVariableDebtToken.sol";
import {IAToken} from "./IAToken.sol";
import {IPoolDataProvider} from "./IPoolDataProvider.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";

import {AaveLogicLib} from "./AaveLogicLib.sol";

import {IAaveLogicLens} from "./IAaveLogicLens.sol";

/// @title AaveLogicLens
/// @notice A lens contract to extract information from Aave V3
/// @dev This contract interacts with Aave V3 and provides helper methods for fetching user-specific data
contract AaveLogicLens is IAaveLogicLens {
    // =========================
    // Constructor
    // =========================

    IPoolAddressesProvider private immutable poolAddressesProvider;

    constructor(IPoolAddressesProvider _poolAddressesProvider) {
        poolAddressesProvider = _poolAddressesProvider;
    }

    // =========================
    // View Functions
    // =========================

    /// @inheritdoc IAaveLogicLens
    function getSupplyAmount(
        address supplyToken,
        address user
    ) external view returns (uint256) {
        address aSupplyToken = AaveLogicLib.aSupplyTokenAddress(
            supplyToken,
            IPool(poolAddressesProvider.getPool())
        );
        return AaveLogicLib.getSupplyAmount(aSupplyToken, user);
    }

    /// @inheritdoc IAaveLogicLens
    function getTotalDebt(
        address debtToken,
        address user
    ) external view returns (uint256) {
        address aDebtToken = AaveLogicLib.aDebtTokenAddress(
            debtToken,
            IPool(poolAddressesProvider.getPool())
        );
        return AaveLogicLib.getTotalDebt(aDebtToken, user);
    }

    /// @inheritdoc IAaveLogicLens
    function getCurrentHF(
        address user
    ) external view returns (uint256 currentHF) {
        return AaveLogicLib.getCurrentHF(user, poolAddressesProvider);
    }

    /// @inheritdoc IAaveLogicLens
    function getCurrentLiquidationThreshold(
        address token
    ) external view returns (uint256 currentLiquidationThreshold_1e4) {
        return
            AaveLogicLib.getCurrentLiquidationThreshold(
                token,
                poolAddressesProvider
            );
    }
}

