// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IERC20} from "./contracts_IERC20.sol";
import {IERC20Detailed} from "./IERC20Detailed.sol";
import {GPv2SafeERC20} from "./GPv2SafeERC20.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {DataTypes} from "./DataTypes.sol";
import {CollateralLogic} from "./CollateralLogic.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {PerpetualDebtLogic} from "./PerpetualDebtLogic.sol";
import {PerpetualDebtConfiguration} from "./PerpetualDebtConfiguration.sol";
import {CollateralConfiguration} from "./CollateralConfiguration.sol";
import {IAssetToken} from "./IAssetToken.sol";
import {ILiabilityToken} from "./ILiabilityToken.sol";
import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";
import {SafeMath} from "./SafeMath.sol";

import "./console.sol";

/**
 * @title LiquidationLogic library
 * @author Tazz Labs, inspired by AAVE v3
 * @notice Implements actions involving account liquidations
 **/
library LiquidationLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using CollateralLogic for DataTypes.CollateralData;
    using PerpetualDebtLogic for DataTypes.PerpetualDebtData;
    using CollateralConfiguration for DataTypes.CollateralConfigurationMap;
    using PerpetualDebtConfiguration for DataTypes.PerpDebtConfigurationMap;
    using GPv2SafeERC20 for IERC20;
    using SafeMath for uint256;

    event LiquidationCall(
        address indexed collateralAsset,
        address indexed user,
        uint256 debtNotionalToCover,
        uint256 assetNotionalCharged,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveCollateral
    );

    /**
     * @dev Default percentage of borrower's debt to be repaid in a liquidation.
     * @dev Percentage applied when the users health factor is above `CLOSE_FACTOR_HF_THRESHOLD`
     * Expressed in bps, a value of 0.5e4 results in 50.00%
     */
    uint256 internal constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 0.5e4;

    /**
     * @dev Maximum percentage of borrower's debt to be repaid in a liquidation
     * @dev Percentage applied when the users health factor is below `CLOSE_FACTOR_HF_THRESHOLD`
     * Expressed in bps, a value of 1e4 results in 100.00%
     */
    uint256 public constant MAX_LIQUIDATION_CLOSE_FACTOR = 1e4;

    /**
     * @dev This constant represents below which health factor value it is possible to liquidate
     * an amount of debt corresponding to `MAX_LIQUIDATION_CLOSE_FACTOR`.
     * A value of 0.95e18 results in 0.95
     */
    uint256 public constant CLOSE_FACTOR_HF_THRESHOLD = 0.95e18;

    struct LiquidationCallLocalVars {
        uint256 userCollateralBalance;
        uint256 userTotalDebtNotional;
        uint256 actualDebtNotionalToLiquidate;
        uint256 actualCollateralToLiquidate;
        uint256 actualAssetNotionalToCharge;
        uint256 liquidationBonus;
        uint256 healthFactor;
        uint256 liquidationProtocolFeeAmount;
        IAssetToken zToken;
        ILiabilityToken dToken;
        IERC20 collateralToken;
    }

    /**
     * @notice Function to liquidate a position if its Health Factor drops below 1. The caller (liquidator)
     * covers `debtNotionalToCover` amount of debt of the user getting liquidated, and receives
     * a proportional amount of the `collateralAsset` plus a bonus to cover market risk
     * @dev Emits the `LiquidationCall()` event
     * @param collateralsData The state of all the collaterals
     * @param collateralsList The addresses of all the active collaterals
     * @param perpDebt The perpetual debt data
     * @param params The additional parameters needed to execute the liquidation function
     **/
    function executeLiquidationCall(
        mapping(address => DataTypes.CollateralData) storage collateralsData,
        mapping(uint256 => address) storage collateralsList,
        DataTypes.PerpetualDebtData storage perpDebt,
        DataTypes.ExecuteLiquidationCallParams memory params
    ) external {
        LiquidationCallLocalVars memory vars;

        DataTypes.CollateralData storage collateral = collateralsData[params.collateralAsset];

        perpDebt.refinance();

        (, , , , vars.healthFactor, ) = GenericLogic.calculateUserAccountData(
            collateralsData,
            collateralsList,
            perpDebt,
            DataTypes.CalculateUserAccountDataParams({
                collateralsCount: params.collateralsCount,
                user: params.user,
                oracle: params.priceOracle
            })
        );

        (vars.userTotalDebtNotional, vars.actualDebtNotionalToLiquidate) = _calculateDebtNotional(
            perpDebt,
            params,
            vars.healthFactor
        );

        ValidationLogic.validateLiquidationCall(
            collateral,
            perpDebt,
            DataTypes.ValidateLiquidationCallParams({
                totalDebtNotional: vars.userTotalDebtNotional,
                healthFactor: vars.healthFactor
            })
        );

        //gather info
        vars.zToken = perpDebt.getAsset();
        vars.dToken = perpDebt.getLiability();
        vars.collateralToken = IERC20(params.collateralAsset);
        vars.liquidationBonus = collateral.configuration.getLiquidationBonus();
        vars.userCollateralBalance = collateral.balances[params.user];

        (
            vars.actualCollateralToLiquidate,
            vars.actualDebtNotionalToLiquidate,
            vars.actualAssetNotionalToCharge,
            vars.liquidationProtocolFeeAmount
        ) = _calculateAvailableCollateralToLiquidate(
            collateral,
            perpDebt,
            AvailableCollateralToLiquidateParams({
                collateralToken: vars.collateralToken,
                zToken: vars.zToken,
                dToken: vars.dToken,
                userDebtNotionalBalance: vars.userTotalDebtNotional,
                debtNotionalToCover: vars.actualDebtNotionalToLiquidate,
                userCollateralBalance: vars.userCollateralBalance,
                liquidationBonus: vars.liquidationBonus,
                oracle: IPriceOracleGetter(params.priceOracle)
            })
        );

        perpDebt.burnAndDistribute(
            msg.sender,
            params.user,
            vars.actualAssetNotionalToCharge,
            vars.actualDebtNotionalToLiquidate
        );

        // Transfer fee to treasury if it is non-zero
        if (vars.liquidationProtocolFeeAmount != 0) {
            //TODO
        }

        if (params.receiveCollateral) {
            //Transfer collateral from params.user balance in Guild to msg.sender wallet
            collateral.balances[params.user] = collateral.balances[params.user].sub(vars.actualCollateralToLiquidate);
            collateral.totalBalance = collateral.totalBalance.sub(vars.actualCollateralToLiquidate);
            IERC20(params.collateralAsset).safeTransfer(msg.sender, vars.actualCollateralToLiquidate);
        } else {
            //Transfer collateral from params.user balance in Guild to msg.sender balance in Guild
            collateral.balances[params.user] = collateral.balances[params.user].sub(vars.actualCollateralToLiquidate);
            collateral.balances[msg.sender] = collateral.balances[msg.sender].add(vars.actualCollateralToLiquidate);
        }

        emit LiquidationCall(
            params.collateralAsset,
            params.user,
            vars.actualDebtNotionalToLiquidate,
            vars.actualAssetNotionalToCharge,
            vars.actualCollateralToLiquidate,
            msg.sender,
            params.receiveCollateral
        );
    }

    /**
     * @notice Calculates the total debt of the user and the actual amount to liquidate depending on the health factor
     * and corresponding close factor.
     * @dev If the Health Factor is below CLOSE_FACTOR_HF_THRESHOLD, the close factor is increased to MAX_LIQUIDATION_CLOSE_FACTOR
     * @param perpDebt The perpetual debt of the Guild
     * @param params The additional parameters needed to execute the liquidation function
     * @param healthFactor The health factor of the position
     * @return The total debt notional of the user
     * @return The actual debt to liquidate as a function of the closeFactor and debtNotionalToCover parameter
     */
    function _calculateDebtNotional(
        DataTypes.PerpetualDebtData storage perpDebt,
        DataTypes.ExecuteLiquidationCallParams memory params,
        uint256 healthFactor
    ) internal view returns (uint256, uint256) {
        uint256 userTotalDebtNotional = perpDebt.getLiability().balanceNotionalOf(params.user);

        uint256 closeFactor = healthFactor > CLOSE_FACTOR_HF_THRESHOLD
            ? DEFAULT_LIQUIDATION_CLOSE_FACTOR
            : MAX_LIQUIDATION_CLOSE_FACTOR;

        uint256 maxLiquidatableDebtNotional = userTotalDebtNotional.percentMul(closeFactor);

        uint256 actualDebtNotionalToLiquidate = params.debtNotionalToCover > maxLiquidatableDebtNotional
            ? maxLiquidatableDebtNotional
            : params.debtNotionalToCover;

        return (userTotalDebtNotional, actualDebtNotionalToLiquidate);
    }

    /*
     * @param collateralToken The collateral token being liquidated
     * @param zToken The asset token used to repay the debt
     * @param dToken The liability token being repaid
     * @param userDebtNotionalBalance The total debt amount of the account being liquidated
     * @param debtNotionalToCover The debt amount the liquidator wants to cover
     * @param userCollateralBalance The collateral balance for the specific `collateralAsset` of the user being liquidated
     * @param liquidationBonus The collateral bonus percentage to receive as result of the liquidation
     */
    struct AvailableCollateralToLiquidateParams {
        IERC20 collateralToken;
        IAssetToken zToken;
        ILiabilityToken dToken;
        uint256 userDebtNotionalBalance;
        uint256 debtNotionalToCover;
        uint256 userCollateralBalance;
        uint256 liquidationBonus;
        IPriceOracleGetter oracle;
    }

    struct AvailableCollateralToLiquidateLocalVars {
        uint256 collateralPrice;
        uint256 assetPrice;
        uint256 maxCollateralToLiquidate;
        uint256 baseCollateral;
        uint256 bonusCollateral;
        uint256 debtDecimals;
        uint256 collateralDecimals;
        uint256 moneyDecimals;
        uint256 debtUnit;
        uint256 collateralUnit;
        uint256 moneyUnit;
        uint256 collateralAmount;
        uint256 liabilityNotionalAmountRepaid;
        uint256 assetNotionalAmountNeeded;
        uint256 liquidationProtocolFeePercentage;
        uint256 liquidationProtocolFee;
    }

    /**
     * @notice Calculates how much of a specific collateral can be liquidated, given
     * a certain amount of debt asset.
     * @dev This function needs to be called after all the checks to validate the liquidation have been performed,
     *   otherwise it might fail.
     * @param collateral The data of the collateral against which to liquidate debt
     * @param perpDebt The perpetual debt of the Guild
 
     * @return The maximum amount of collatertal that is possible to liquidate given all the liquidation constraints (user balance, close factor)
     * @return The debt Notional being repaid
     * @return The zToken amount needed for this liquidation (in lieu of money)
     * @return The fee taken from the liquidation bonus amount to be paid to the protocol
     **/
    function _calculateAvailableCollateralToLiquidate(
        DataTypes.CollateralData storage collateral,
        DataTypes.PerpetualDebtData storage perpDebt,
        AvailableCollateralToLiquidateParams memory params
    )
        internal
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        AvailableCollateralToLiquidateLocalVars memory vars;

        vars.collateralPrice = params.oracle.getAssetPrice(address(params.collateralToken)); // in BASE_CURRENCY UNITS
        vars.assetPrice = perpDebt.getAssetBasePrice(address(params.oracle)); // in BASE_CURRENCY UNITS

        vars.collateralDecimals = collateral.configuration.getDecimals();
        vars.debtDecimals = IERC20Detailed(address(perpDebt.getLiability())).decimals();
        vars.moneyDecimals = IERC20Detailed(params.oracle.BASE_CURRENCY()).decimals();

        unchecked {
            vars.collateralUnit = 10**vars.collateralDecimals;
            vars.debtUnit = 10**vars.debtDecimals;
            vars.moneyUnit = 10**vars.moneyDecimals;
        }

        vars.liquidationProtocolFeePercentage = collateral.configuration.getLiquidationProtocolFee();

        //branch depending on whether loan is in underwater.
        uint256 totalDebtNotionalMoneyUnits = params
            .userDebtNotionalBalance
            .mul(vars.moneyUnit)
            .div(vars.debtUnit)
            .percentMul(params.liquidationBonus);

        uint256 totalCollateralValue = params.userCollateralBalance.mul(vars.collateralPrice).div(vars.collateralUnit);

        if (totalCollateralValue < totalDebtNotionalMoneyUnits) {
            //liquidate collateral proportional to debt
            if (params.debtNotionalToCover > params.userDebtNotionalBalance) {
                vars.liabilityNotionalAmountRepaid = params.userDebtNotionalBalance;
                vars.collateralAmount = params.userCollateralBalance;
            } else {
                vars.liabilityNotionalAmountRepaid = params.debtNotionalToCover;
                vars.collateralAmount = params.userCollateralBalance.mul(params.debtNotionalToCover).div(
                    params.userDebtNotionalBalance
                );
            }
        } else {
            //calculate how much collateral is to be liquidated given debtToCover

            // This is the base collateral to liquidate based on the given debt (liability) to cover
            vars.baseCollateral =
                (params.debtNotionalToCover * vars.moneyUnit * vars.collateralUnit) /
                (vars.collateralPrice * vars.debtUnit);

            vars.maxCollateralToLiquidate = vars.baseCollateral.percentMul(params.liquidationBonus);

            if (vars.maxCollateralToLiquidate > params.userCollateralBalance) {
                vars.collateralAmount = params.userCollateralBalance;
                vars.liabilityNotionalAmountRepaid = ((vars.collateralPrice * vars.collateralAmount * vars.debtUnit) /
                    (vars.moneyUnit * vars.collateralUnit)).percentDiv(params.liquidationBonus);
            } else {
                vars.collateralAmount = vars.maxCollateralToLiquidate;
                vars.liabilityNotionalAmountRepaid = params.debtNotionalToCover;
            }
        }

        // zToken (asset) value requested = dToken (liability) Notional to be repaid.
        // zTokenAmount = zTokenValue / zTokenPrice
        uint256 assetAmountNeeded = (vars.liabilityNotionalAmountRepaid * vars.moneyUnit) / vars.assetPrice;

        vars.assetNotionalAmountNeeded = params.zToken.baseToNotional(assetAmountNeeded);

        if (vars.liquidationProtocolFeePercentage != 0) {
            vars.bonusCollateral = vars.collateralAmount - vars.collateralAmount.percentDiv(params.liquidationBonus);

            vars.liquidationProtocolFee = vars.bonusCollateral.percentMul(vars.liquidationProtocolFeePercentage);

            return (
                vars.collateralAmount - vars.liquidationProtocolFee,
                vars.liabilityNotionalAmountRepaid,
                vars.assetNotionalAmountNeeded,
                vars.liquidationProtocolFee
            );
        } else {
            return (vars.collateralAmount, vars.liabilityNotionalAmountRepaid, vars.assetNotionalAmountNeeded, 0);
        }
    }
}

