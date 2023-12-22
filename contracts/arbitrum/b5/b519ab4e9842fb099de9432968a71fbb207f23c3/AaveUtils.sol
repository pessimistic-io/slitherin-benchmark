//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IERC20Metadata as IERC20} from "./IERC20Metadata.sol";
import "./IPool.sol";

import {ReserveConfiguration} from "./ReserveConfiguration.sol";
import {ReserveLogic} from "./ReserveLogic.sol";

library AaveUtils {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using ReserveLogic for DataTypes.ReserveData;

    function collateralBalance(IPool pool, IERC20 asset, address account) internal view returns (uint256) {
        return IERC20(pool.getReserveData(address(asset)).aTokenAddress).balanceOf(account);
    }

    function debtBalance(IPool pool, IERC20 asset, address account) internal view returns (uint256) {
        return IERC20(pool.getReserveData(address(asset)).variableDebtTokenAddress).balanceOf(account);
    }

    function eModeCategory(IPool pool, IERC20 asset) internal view returns (uint256) {
        return pool.getReserveData(address(asset)).configuration.getEModeCategory();
    }

    function eModeCategory(IPool pool, IERC20 collateralAsset, IERC20 debtAsset) internal view returns (uint256) {
        uint256 eModeCat = eModeCategory(pool, collateralAsset);
        return eModeCat > 0 && eModeCat == eModeCategory(pool, debtAsset) ? eModeCat : 0;
    }
}

