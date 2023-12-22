/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import "./Account.sol";
import "./ProtocolRiskConfiguration.sol";
import "./CollateralConfiguration.sol";
import "./ParameterError.sol";
import "./ILiquidationModule.sol";
import "./SafeCast.sol";
import "./Collateral.sol";

import {mulUDxUint} from "./PrbMathHelper.sol";

/**
 * @title Module for liquidated accounts
 * @dev See ILiquidationModule
 */

contract LiquidationModule is ILiquidationModule {
    using ProtocolRiskConfiguration for ProtocolRiskConfiguration.Data;
    using CollateralConfiguration for CollateralConfiguration.Data;
    using Account for Account.Data;
    using SafeCastU256 for uint256;
    using SafeCastI256 for int256;
    using Collateral for Collateral.Data;

    function extractLiquidatorReward(
        uint128 liquidatedAccountId,
        address collateralType,
        uint256 imPreClose,
        uint256 imPostClose
    ) internal returns (uint256 liquidatorRewardAmount) {
        Account.Data storage account = Account.load(liquidatedAccountId);

        UD60x18 liquidatorRewardParameter = ProtocolRiskConfiguration.load().liquidatorRewardParameter;
        uint256 liquidationBooster = CollateralConfiguration.load(collateralType).liquidationBooster;

        if (mulUDxUint(liquidatorRewardParameter, imPreClose) >= liquidationBooster) {
            liquidatorRewardAmount = mulUDxUint(liquidatorRewardParameter, imPreClose - imPostClose);
            account.collaterals[collateralType].decreaseCollateralBalance(liquidatorRewardAmount);
            emit Collateral.CollateralUpdate(
                liquidatedAccountId, collateralType, -liquidatorRewardAmount.toInt(), block.timestamp
            );
        } else {
            if (imPostClose != 0) {
                revert PartialLiquidationNotIncentivized(liquidatedAccountId, imPreClose, imPostClose);
            }

            liquidatorRewardAmount = liquidationBooster;
            account.collaterals[collateralType].decreaseLiquidationBoosterBalance(liquidatorRewardAmount);
            emit Collateral.LiquidatorBoosterUpdate(
                liquidatedAccountId, collateralType, -liquidatorRewardAmount.toInt(), block.timestamp
            );
        }
    }

    /**
     * @inheritdoc ILiquidationModule
     */
    function liquidate(uint128 liquidatedAccountId, uint128 liquidatorAccountId, address collateralType)
        external
        returns (uint256 liquidatorRewardAmount)
    {
        Account.Data storage account = Account.exists(liquidatedAccountId);
        (bool liquidatable, uint256 imPreClose,) = account.isLiquidatable(collateralType);

        if (!liquidatable) {
            revert AccountNotLiquidatable(liquidatedAccountId);
        }

        account.closeAccount(collateralType);
        (uint256 imPostClose,) = account.getMarginRequirements(collateralType);

        if (imPreClose <= imPostClose) {
            revert AccountExposureNotReduced(liquidatedAccountId, imPreClose, imPostClose);
        }

        liquidatorRewardAmount = extractLiquidatorReward(liquidatedAccountId, collateralType, imPreClose, imPostClose);

        Account.Data storage liquidatorAccount = Account.exists(liquidatorAccountId);
        liquidatorAccount.collaterals[collateralType].increaseCollateralBalance(liquidatorRewardAmount);
        emit Collateral.CollateralUpdate(
            liquidatorAccountId, collateralType, liquidatorRewardAmount.toInt(), block.timestamp
        );

        emit Liquidation(
            liquidatedAccountId,
            collateralType,
            msg.sender,
            liquidatorAccountId,
            liquidatorRewardAmount,
            imPreClose,
            imPostClose,
            block.timestamp
        );
    }
}

