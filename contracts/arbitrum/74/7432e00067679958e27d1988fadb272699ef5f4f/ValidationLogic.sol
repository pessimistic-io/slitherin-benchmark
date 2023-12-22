// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IERC20} from "./contracts_IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {Address} from "./Address.sol";
import {Errors} from "./Errors.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {DataTypes} from "./DataTypes.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {CollateralLogic} from "./CollateralLogic.sol";
import {SafeCast} from "./SafeCast.sol";
import {CollateralConfiguration} from "./CollateralConfiguration.sol";
import {PerpetualDebtConfiguration} from "./PerpetualDebtConfiguration.sol";
import {PerpetualDebtConfiguration} from "./PerpetualDebtConfiguration.sol";

import "./console.sol";

/**
 * @title ValidationLogic library
 * @author Tazz Labs
 * @notice Implements functions to validate the different actions of the protocol
 */
library ValidationLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeCast for uint256;
    using Address for address;
    using CollateralLogic for DataTypes.CollateralData;
    using CollateralConfiguration for DataTypes.CollateralConfigurationMap;
    using PerpetualDebtConfiguration for DataTypes.PerpDebtConfigurationMap;

    /**
     * @dev Minimum health factor to consider a user position healthy
     * A value of 1e18 results in 1
     */
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;

    struct ValidateBorrowLocalVars {
        uint256 mintAmountNotional;
        uint256 currentLtv;
        uint256 collateralNeededInBaseCurrency;
        uint256 userCollateralInBaseCurrency;
        uint256 userDebtInBaseCurrency;
        uint256 healthFactor;
        uint256 collateralDecimals;
        uint256 amountNotionalInBaseCurrency;
        uint256 totalDebtNotional;
        uint256 mintCap;
        bool isFrozen;
        bool isPaused;
    }

    /**
     * @notice Validates a borrow action.
     * @param collateralData The state of all the collaterals
     * @param collateralList The addresses of all the active collaterals
     * @param params Additional params needed for the validation
     */
    function validateBorrow(
        mapping(address => DataTypes.CollateralData) storage collateralData,
        mapping(uint256 => address) storage collateralList,
        DataTypes.PerpetualDebtData memory perpDebt,
        DataTypes.ValidateBorrowParams memory params
    ) internal view {
        require(params.amount != 0, Errors.AMOUNT_NEED_TO_BE_GREATER);

        ValidateBorrowLocalVars memory vars;

        // Validate states
        (vars.isFrozen, vars.isPaused) = perpDebt.configuration.getFlags();
        require(!vars.isPaused, Errors.PERPETUAL_DEBT_PAUSED);
        require(!vars.isFrozen, Errors.PERPETUAL_DEBT_FROZEN);

        // Validate caps
        // @dev - debtNotional in WADs
        vars.mintAmountNotional = perpDebt.zToken.baseToNotional(params.amount);
        vars.totalDebtNotional = perpDebt.dToken.totalNotionalSupply();
        (vars.mintCap) = perpDebt.configuration.getCaps();
        require(
            vars.mintCap == 0 || (vars.totalDebtNotional + vars.mintAmountNotional) <= vars.mintCap * (10**18),
            Errors.PERPETUAL_DEBT_CAP_EXCEEDED
        );

        // Validate health factors
        (
            vars.userCollateralInBaseCurrency,
            vars.userDebtInBaseCurrency,
            vars.currentLtv,
            ,
            vars.healthFactor,

        ) = GenericLogic.calculateUserAccountData(
            collateralData,
            collateralList,
            perpDebt,
            DataTypes.CalculateUserAccountDataParams({
                collateralsCount: params.collateralsCount,
                user: params.user,
                oracle: params.oracle
            })
        );
        require(vars.userCollateralInBaseCurrency != 0, Errors.COLLATERAL_BALANCE_IS_ZERO);
        require(vars.currentLtv != 0, Errors.LTV_VALIDATION_FAILED);
        require(
            vars.healthFactor > HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
        );

        //convert amountNotional (in WAD) to BaseCurrency
        uint256 moneyUnit;
        unchecked {
            moneyUnit = 10**IERC20Metadata(address(perpDebt.money)).decimals();
        }
        vars.amountNotionalInBaseCurrency = moneyUnit.wadMul(vars.mintAmountNotional);

        //add the current already borrowed amount to the amount requested to calculate the total collateral needed.
        vars.collateralNeededInBaseCurrency = (vars.userDebtInBaseCurrency + vars.amountNotionalInBaseCurrency)
            .percentDiv(vars.currentLtv); //LTV is calculated in percentage

        require(
            vars.collateralNeededInBaseCurrency <= vars.userCollateralInBaseCurrency,
            Errors.COLLATERAL_CANNOT_COVER_NEW_BORROW
        );
    }

    /**
     * @notice Validates a repay action.
     * @param amountSent The amount sent for the repayment. Can be an actual value or uint(-1)
     */
    function validateRepay(DataTypes.PerpDebtConfigurationMap memory perpDebtConfig, uint256 amountSent) internal pure {
        require(amountSent != 0, Errors.INVALID_AMOUNT);

        (, bool isPaused) = perpDebtConfig.getFlags();
        require(!isPaused, Errors.PERPETUAL_DEBT_PAUSED);
    }

    /**
     * @notice Validates a withdraw action.
     * @param collateralConfig The config data of collateral being withdrawn
     * @param amount The amount to be withdrawn
     * @param userBalance The balance of the user
     */
    function validateWithdraw(
        DataTypes.CollateralConfigurationMap memory collateralConfig,
        uint256 amount,
        uint256 userBalance
    ) internal pure {
        require(amount != 0, Errors.INVALID_AMOUNT);
        require(amount <= userBalance, Errors.NOT_ENOUGH_AVAILABLE_USER_BALANCE);

        (bool isActive, , bool isPaused) = collateralConfig.getFlags();
        require(isActive, Errors.COLLATERAL_INACTIVE);
        require(!isPaused, Errors.COLLATERAL_PAUSED);
    }

    /**
     * @notice Validates a deposit action.
     * @param collateralConfig The config data of collateral being deposited
     * @param collateral The collateral guild object
     * @param onBehalfOf The user to which collateral will be deposited
     * @param amount The amount to be deposited
     **/
    function validateDeposit(
        DataTypes.CollateralConfigurationMap memory collateralConfig,
        DataTypes.CollateralData storage collateral,
        address onBehalfOf,
        uint256 amount
    ) internal view {
        require(amount != 0, Errors.INVALID_AMOUNT);

        (bool isActive, bool isFrozen, bool isPaused) = collateralConfig.getFlags();
        require(isActive, Errors.COLLATERAL_INACTIVE);
        require(!isPaused, Errors.COLLATERAL_PAUSED);
        require(!isFrozen, Errors.COLLATERAL_FROZEN);

        (uint256 supplyCap, uint256 userSupplyCap) = collateralConfig.getCaps();
        uint256 collateralUnits = 10**collateralConfig.getDecimals();

        //@dev supplyCap encoded with 0 decimal places (e.g, 1 -> 1 token in collateral's own unit)
        require(
            supplyCap == 0 || (collateral.totalBalance + amount) <= supplyCap * collateralUnits,
            Errors.SUPPLY_CAP_EXCEEDED
        );

        //@dev userSupplyCap encoded with 2 decimal places (e.g, 100 -> 1 token in collateral's own unit)
        require(
            userSupplyCap == 0 || (collateral.balances[onBehalfOf] + amount) <= (userSupplyCap * collateralUnits) / 100,
            Errors.SUPPLY_CAP_EXCEEDED
        );
    }

    /**
     * @notice Validates the health factor of a user.
     * @param collateralsData The collateral data
     * @param collateralsList The addresses of all the active collaterals
     * @param collateralsCount The number of available collaterals
     * @param user The user to validate health factor of
     * @param oracle The price oracle
     */
    function validateHealthFactor(
        mapping(address => DataTypes.CollateralData) storage collateralsData,
        mapping(uint256 => address) storage collateralsList,
        DataTypes.PerpetualDebtData memory perpDebt,
        uint256 collateralsCount,
        address user,
        address oracle
    ) internal view returns (uint256, bool) {
        (, , , , uint256 healthFactor, bool hasZeroLtvCollateral) = GenericLogic.calculateUserAccountData(
            collateralsData,
            collateralsList,
            perpDebt,
            DataTypes.CalculateUserAccountDataParams({collateralsCount: collateralsCount, user: user, oracle: oracle})
        );

        require(
            healthFactor >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD,
            Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
        );

        return (healthFactor, hasZeroLtvCollateral);
    }

    /**
     * @notice Validates the health factor of a user and the ltv of the asset being withdrawn.
     * @param collateralsData The collateral data
     * @param collateralsList The addresses of all the active collaterals
     * @param collateralsCount The number of available collaterals
     * @param user The user to validate health factor of
     * @param oracle The price oracle
     * @param asset The asset for which the ltv will be validated
     */
    function validateHFAndLtv(
        mapping(address => DataTypes.CollateralData) storage collateralsData,
        mapping(uint256 => address) storage collateralsList,
        DataTypes.PerpetualDebtData memory perpDebt,
        uint256 collateralsCount,
        address user,
        address oracle,
        address asset
    ) internal view {
        DataTypes.CollateralConfigurationMap memory collateralConfiguration = collateralsData[asset].configuration;

        (, bool hasZeroLtvCollateral) = validateHealthFactor(
            collateralsData,
            collateralsList,
            perpDebt,
            collateralsCount,
            user,
            oracle
        );

        //Don't allow withdrawals if any collateral (or specifically, the collateral being withdrawn)
        //if LTVs of collaterals have not been set
        require(!hasZeroLtvCollateral || collateralConfiguration.getLtv() == 0, Errors.LTV_VALIDATION_FAILED);
    }

    struct ValidateLiquidationCallLocalVars {
        bool collateralActive;
        bool perpDebtPaused;
        bool isCollateralEnabled;
    }

    /**
     * @notice Validates the liquidation action.
     * @param collateral The state data of collateral being liquidated
     * @param perpDebt The perpetual Debt state data
     * @param params Additional parameters needed for the validation
     */
    function validateLiquidationCall(
        DataTypes.CollateralData storage collateral,
        DataTypes.PerpetualDebtData storage perpDebt,
        DataTypes.ValidateLiquidationCallParams memory params
    ) internal view {
        ValidateLiquidationCallLocalVars memory vars;

        (vars.collateralActive, , ) = collateral.configuration.getFlags();
        (vars.perpDebtPaused, ) = perpDebt.configuration.getFlags();

        require(vars.collateralActive, Errors.COLLATERAL_INACTIVE);
        require(!vars.perpDebtPaused, Errors.DEBT_PAUSED);

        require(params.totalDebtNotional != 0, Errors.USER_HAS_NO_DEBT);
        require(params.healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD, Errors.HEALTH_FACTOR_NOT_BELOW_THRESHOLD);

        vars.isCollateralEnabled = collateral.configuration.getLiquidationThreshold() != 0;

        //if collateral isn't enabled, it cannot be liquidated
        require(vars.isCollateralEnabled, Errors.COLLATERAL_CANNOT_BE_LIQUIDATED);
    }
}

