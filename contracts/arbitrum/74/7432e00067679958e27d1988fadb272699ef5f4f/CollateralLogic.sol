// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IERC20} from "./contracts_IERC20.sol";
import {GPv2SafeERC20} from "./GPv2SafeERC20.sol";
import {Errors} from "./Errors.sol";
import {DataTypes} from "./DataTypes.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {PerpetualDebtLogic} from "./PerpetualDebtLogic.sol";
import {CollateralConfiguration} from "./CollateralConfiguration.sol";
import {SafeMath} from "./SafeMath.sol";

/**
 * @title Collateral Logic library
 * @author Tazz Labs, inspired by AAVE v3 supplylogic.sol
 * @notice Implements the base logic for collateral deposit/withdraw
 */
library CollateralLogic {
    using GPv2SafeERC20 for IERC20;
    using CollateralConfiguration for DataTypes.CollateralConfigurationMap;
    using PerpetualDebtLogic for DataTypes.PerpetualDebtData;
    using WadRayMath for uint256;
    using SafeMath for uint256;

    // See `IGuild` for descriptions
    event Withdraw(address indexed collateral, address indexed user, address indexed to, uint256 amount);
    event Deposit(address indexed collateral, address user, address indexed onBehalfOf, uint256 amount);

    /**
     * @notice Implements the deposit feature. Through `deposit()`, users deposit collateral to the TAZZ protocol.
     * @dev Emits the `Deposit()` event.
     * @param collateralsData The state of all collaterals
     * @param collateralsList The addresses of all the active collaterals
     * @param params The additional parameters needed to execute the supply function
     */
    function executeDeposit(
        mapping(address => DataTypes.CollateralData) storage collateralsData,
        mapping(uint256 => address) storage collateralsList,
        DataTypes.ExecuteDepositParams memory params
    ) external {
        DataTypes.CollateralData storage collateral = collateralsData[params.asset];
        DataTypes.CollateralConfigurationMap memory collateralConfigCache = collateral.configuration;

        ValidationLogic.validateDeposit(collateralConfigCache, collateral, params.onBehalfOf, params.amount);

        //Transfer asset from msg.sender wallet to Guild (and accrued balance to params.onBehalfOf account internally)
        IERC20(params.asset).safeTransferFrom(msg.sender, address(this), params.amount);
        collateral.balances[params.onBehalfOf] = collateral.balances[params.onBehalfOf].add(params.amount);
        collateral.totalBalance = collateral.totalBalance.add(params.amount);

        emit Deposit(params.asset, msg.sender, params.onBehalfOf, params.amount);
    }

    /**
     * @notice Implements the withdraw feature. Through `withdraw()`, users withdraw collateral (if unencumbered), previously supplied to the Guild
     * @dev Emits the `Withdraw()` event.
     * @param collateralsData The state of all the collaterals
     * @param collateralsList The addresses of all the active collaterals
     * @param params The additional parameters needed to execute the withdraw function
     * @return The actual amount withdrawn
     */
    function executeWithdraw(
        mapping(address => DataTypes.CollateralData) storage collateralsData,
        mapping(uint256 => address) storage collateralsList,
        DataTypes.PerpetualDebtData storage perpetualDebt,
        DataTypes.ExecuteWithdrawParams memory params
    ) external returns (uint256) {
        DataTypes.CollateralData storage collateral = collateralsData[params.asset];
        DataTypes.CollateralConfigurationMap memory collateralConfigCache = collateral.configuration;

        uint256 userLiability = perpetualDebt.getLiability().balanceOf(msg.sender);
        uint256 userBalance = collateral.balances[msg.sender];
        uint256 amountToWithdraw = params.amount;

        if (params.amount == type(uint256).max) {
            amountToWithdraw = userBalance;
        }

        ValidationLogic.validateWithdraw(collateralConfigCache, amountToWithdraw, userBalance);

        //Transfer asset from msg.sender balance in Guild to params.to wallet
        collateral.balances[msg.sender] = collateral.balances[msg.sender].sub(params.amount);
        collateral.totalBalance = collateral.totalBalance.sub(params.amount);
        IERC20(params.asset).safeTransfer(params.to, amountToWithdraw);

        //Validate loans are healthy after withdrawal
        if (userLiability > 0) {
            //Refinance perpetual debt, to ensure interest has accrued
            perpetualDebt.refinance();

            //validate HealthFactor + Collateral LTVs
            ValidationLogic.validateHFAndLtv(
                collateralsData,
                collateralsList,
                perpetualDebt,
                params.collateralsCount,
                msg.sender,
                params.oracle,
                params.asset
            );
        }

        emit Withdraw(params.asset, msg.sender, params.to, amountToWithdraw);

        return amountToWithdraw;
    }
}

