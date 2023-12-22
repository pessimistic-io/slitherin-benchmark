// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";
import {IAssetToken} from "./IAssetToken.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {CollateralConfiguration} from "./CollateralConfiguration.sol";
import {PerpetualDebtConfiguration} from "./PerpetualDebtConfiguration.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {DataTypes} from "./DataTypes.sol";
import {PerpetualDebtLogic} from "./PerpetualDebtLogic.sol";
import {SafeMath} from "./SafeMath.sol";

import "./console.sol";

/**
 * @title GenericLogic library
 * @author Tazz Labs
 * @notice Implements protocol-level logic to calculate and validate the state of a user
 */
library GenericLogic {
    // using CollateralConfiguration for DataTypes.CollateralData;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeMath for uint256;
    using CollateralConfiguration for DataTypes.CollateralConfigurationMap;
    using PerpetualDebtConfiguration for DataTypes.PerpDebtConfigurationMap;
    using PerpetualDebtLogic for DataTypes.PerpetualDebtData;

    struct CalculateUserAccountDataVars {
        uint256 assetPrice;
        uint256 assetUnit;
        uint256 userBalanceInBaseCurrency;
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 i;
        uint256 healthFactor;
        uint256 totalCollateralInBaseCurrency;
        uint256 totalDebtNotionalInBaseCurrency;
        uint256 avgLtv;
        uint256 avgLiquidationThreshold;
        address currentCollateralAddress;
        bool hasZeroLtvCollateral;
    }

    /**
     * @notice Calculates the user data across the collaterals.
     * @dev It includes the total liquidity/collateral/borrow balances in the base currency used by the price feed,
     * the average Loan To Value, the average Liquidation Ratio, and the Health factor.
     * @param collateralData The state of all the collaterals
     * @param collateralList The addresses of all the active collaterals
     * @param params Additional parameters needed for the calculation
     * @return The total collateral of the user in the base currency used by the price feed
     * @return The total debt of the user in the base currency used by the price feed
     * @return The average ltv of the user
     * @return The average liquidation threshold of the user
     * @return The health factor of the user (in WADs)
     * @return True if the ltv is zero, false otherwise
     **/
    function calculateUserAccountData(
        mapping(address => DataTypes.CollateralData) storage collateralData,
        mapping(uint256 => address) storage collateralList,
        DataTypes.PerpetualDebtData memory perpDebt,
        DataTypes.CalculateUserAccountDataParams memory params
    )
        internal
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool
        )
    {
        // if (params.userConfig.isEmpty()) {
        //     return (0, 0, 0, 0, type(uint256).max, false);
        // }

        CalculateUserAccountDataVars memory vars;

        while (vars.i < params.collateralsCount) {
            vars.currentCollateralAddress = collateralList[vars.i];

            if (vars.currentCollateralAddress == address(0)) {
                unchecked {
                    ++vars.i;
                }
                continue;
            }

            DataTypes.CollateralData storage currentCollateral = collateralData[vars.currentCollateralAddress];

            (vars.ltv, vars.liquidationThreshold, , vars.decimals) = currentCollateral.configuration.getParams();

            unchecked {
                vars.assetUnit = 10**vars.decimals;
            }

            //get collateral asset price in base currency
            vars.assetPrice = IPriceOracleGetter(params.oracle).getAssetPrice(vars.currentCollateralAddress);

            if (vars.liquidationThreshold != 0) {
                vars.userBalanceInBaseCurrency = _getUserBalanceInBaseCurrency(
                    params.user,
                    currentCollateral,
                    vars.assetPrice,
                    vars.assetUnit
                );

                vars.totalCollateralInBaseCurrency += vars.userBalanceInBaseCurrency;

                if (vars.ltv != 0) {
                    vars.avgLtv += vars.userBalanceInBaseCurrency * vars.ltv;
                } else {
                    vars.hasZeroLtvCollateral = true;
                }

                vars.avgLiquidationThreshold += vars.userBalanceInBaseCurrency * vars.liquidationThreshold;
            }

            unchecked {
                ++vars.i;
            }
        }

        vars.totalDebtNotionalInBaseCurrency = _getUserDebtNotionalInBaseCurrency(params.user, perpDebt);

        unchecked {
            vars.avgLtv = vars.totalCollateralInBaseCurrency != 0
                ? vars.avgLtv / vars.totalCollateralInBaseCurrency
                : 0;
            vars.avgLiquidationThreshold = vars.totalCollateralInBaseCurrency != 0
                ? vars.avgLiquidationThreshold / vars.totalCollateralInBaseCurrency
                : 0;
        }

        //Calculate rounded healthFactor in WADs
        vars.healthFactor = (vars.totalDebtNotionalInBaseCurrency == 0)
            ? type(uint256).max
            : (vars.totalCollateralInBaseCurrency.percentMul(vars.avgLiquidationThreshold)).wadDiv(
                vars.totalDebtNotionalInBaseCurrency
            );

        return (
            vars.totalCollateralInBaseCurrency,
            vars.totalDebtNotionalInBaseCurrency,
            vars.avgLtv,
            vars.avgLiquidationThreshold,
            vars.healthFactor,
            vars.hasZeroLtvCollateral
        );
    }

    /**
     * @notice Calculates the maximum amount that can be borrowed depending on the available collateral, the total debt
     * and the average Loan To Value
     * @param totalCollateralInBaseCurrency The total collateral in the base currency used by the price feed
     * @param totalDebtNotionalInBaseCurrency The total borrow balance in the base currency used by the price feed
     * @param ltv The average loan to value
     * @return The amount available to borrow in the base currency of the used by the price feed
     * @return The amount of zTokens available to borrow
     **/
    function calculateAvailableBorrows(
        uint256 totalCollateralInBaseCurrency,
        uint256 totalDebtNotionalInBaseCurrency,
        uint256 ltv,
        DataTypes.PerpetualDebtData storage perpDebt,
        DataTypes.CalculateUserAccountDataParams memory params
    )
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 availableBorrowsInBaseCurrency = totalCollateralInBaseCurrency.percentMul(ltv);
        if (availableBorrowsInBaseCurrency < totalDebtNotionalInBaseCurrency) {
            return (0, 0, 0);
        }
        availableBorrowsInBaseCurrency = availableBorrowsInBaseCurrency - totalDebtNotionalInBaseCurrency;

        //convert amountNotional in BaseCurrency to WAD
        uint256 moneyUnit;
        unchecked {
            moneyUnit = 10**IERC20Metadata(address(perpDebt.money)).decimals();
        }
        uint256 availableNotionalBorrows = availableBorrowsInBaseCurrency.wadDiv(moneyUnit);

        // convert to zTokens
        IAssetToken zToken = perpDebt.getAsset();
        uint256 availableBorrowsInZTokens = zToken.notionalToBase(availableNotionalBorrows);

        // ensure available borrows does not exceed perpdebt caps
        uint256 zTokenCap = perpDebt.configuration.getMintCap();
        if (zTokenCap > 0) {
            zTokenCap = zTokenCap * WadRayMath.wad();
            uint256 zTokenSupply = zToken.totalSupply();
            if (zTokenSupply + availableBorrowsInZTokens > zTokenCap) {
                //Limit available zToken borrow given Guild cap (otherwise incorrect quote is being given)
                availableBorrowsInZTokens = zTokenCap - zTokenSupply;
                availableNotionalBorrows = zToken.baseToNotional(availableBorrowsInZTokens);
                //convert amountNotional from WAD to BaseCurrency
                availableBorrowsInBaseCurrency = availableNotionalBorrows.wadMul(moneyUnit);
            }
        }

        return (availableBorrowsInBaseCurrency, availableBorrowsInZTokens, availableNotionalBorrows);
    }

    /**
     * @notice Calculates total debt of the user in the based currency used to normalize the values of the assets
     * @param user The address of the user
     * @param perpDebt The perpetual debt data
     * @return userTotalDebtNotional The total debt of the user normalized to the base currency
     **/
    function _getUserDebtNotionalInBaseCurrency(address user, DataTypes.PerpetualDebtData memory perpDebt)
        private
        view
        returns (uint256 userTotalDebtNotional)
    {
        userTotalDebtNotional = perpDebt.dToken.balanceNotionalOf(user);

        uint256 moneyUnit;
        unchecked {
            moneyUnit = 10**IERC20Metadata(address(perpDebt.money)).decimals();
        }
        //change decimals to money (baseCurrency) decimal unit, rounding to nearest unit
        userTotalDebtNotional = moneyUnit.wadMul(userTotalDebtNotional);
    }

    /**
     * @notice Calculates total dToken balance of the user in the based currency used by the price oracle
     * @param user The address of the user
     * @param collaterals The data of the collateral for which the total dToken balance of the user is being calculated
     * @param assetPrice The price of the asset for which the total dToken balance of the user is being calculated
     * @return The total dToken balance of the user normalized to the base currency of the price oracle
     **/
    function _getUserBalanceInBaseCurrency(
        address user,
        DataTypes.CollateralData storage collaterals,
        uint256 assetPrice,
        uint256 assetUnit
    ) private view returns (uint256) {
        uint256 balance = assetPrice * collaterals.balances[user];
        //change decimals to money (baseCurrency) decimal unit, flooring to nearest unit

        unchecked {
            return balance / assetUnit;
        }
    }
}

