// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {DataTypes} from "./DataTypes.sol";
import {PerpetualDebtLogic} from "./PerpetualDebtLogic.sol";
import {ValidationLogic} from "./ValidationLogic.sol";

//debugging
import "./console.sol";

/**
 * @title Borrowing Logic library
 * @author Tazz Labs, inspired by AAVEv3
 * @notice Implements the base logic for all the actions related to borrowing
 */

library BorrowLogic {
    using PerpetualDebtLogic for DataTypes.PerpetualDebtData;

    // See `IGuild` for descriptions
    event Borrow(address indexed user, address indexed onBehalfOf, uint256 amount, uint256 amountNotional);
    event Repay(address indexed user, address indexed onBehalfOf, uint256 amount, uint256 amountNotional);

    /**
     * @notice Implements the borrow feature. Borrowing allows users that provided collateral to draw liquidity from the
     * Tazz protocol proportionally to their collateralization power.
     * @dev  Emits the `Borrow()` event
     * @param collateralData The state of all the collaterals
     * @param collateralList The addresses of all the active collaterals
     * @param perpData The state of all the perpetual data
     * @param params The additional parameters needed to execute the borrow function
     */
    function executeBorrow(
        mapping(address => DataTypes.CollateralData) storage collateralData,
        mapping(uint256 => address) storage collateralList,
        DataTypes.PerpetualDebtData storage perpData,
        DataTypes.ExecuteBorrowParams memory params
    ) public {
        // Update state
        perpData.refinance();

        ValidationLogic.validateBorrow(
            collateralData,
            collateralList,
            perpData,
            DataTypes.ValidateBorrowParams({
                user: params.onBehalfOf,
                amount: params.amount, //notional Amount of debt
                collateralsCount: params.collateralsCount,
                oracle: params.oracle
            })
        );
        perpData.mint(params.user, params.onBehalfOf, params.amount);
        uint256 mintAmountNotional = perpData.getAsset().baseToNotional(params.amount);
        emit Borrow(params.user, params.onBehalfOf, params.amount, mintAmountNotional);
    }

    /**
     * @notice Implements the repay feature. Repaying burns zTokens from msg.senders wallet with an
     * equivalent notional amount of dTokens for the onBehalfOf user (effectively clearing their debt).
     * @dev  Emits the `Repay()` event
     * @param params The additional parameters needed to execute the repay function
     * @return The actual notional amount being repaid
     */
    function executeRepay(DataTypes.PerpetualDebtData storage perpData, DataTypes.ExecuteRepayParams memory params)
        external
        returns (uint256)
    {
        DataTypes.PerpDebtConfigurationMap memory perpDebtConfigCache = perpData.configuration;

        //Update state
        perpData.refinance();

        //Validate repay
        ValidationLogic.validateRepay(perpDebtConfigCache, params.amount);

        //Reduce zTokens depending on max debt that can be repaid
        uint256 debtInZTokens = perpData.getAssetGivenLiability(perpData.getLiability().balanceOf(params.onBehalfOf));
        uint256 paybackAmount = (params.amount > debtInZTokens) ? debtInZTokens : params.amount;
        uint256 paybackAmountNotional = perpData.getAsset().baseToNotional(paybackAmount);

        perpData.burn(msg.sender, params.onBehalfOf, paybackAmount);
        emit Repay(msg.sender, params.onBehalfOf, paybackAmount, paybackAmountNotional);
        return paybackAmountNotional;
    }
}

