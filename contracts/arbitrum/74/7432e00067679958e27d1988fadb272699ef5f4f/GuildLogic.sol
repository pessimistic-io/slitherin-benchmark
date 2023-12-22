// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {GPv2SafeERC20} from "./GPv2SafeERC20.sol";
import {Address} from "./Address.sol";
import {IERC20} from "./contracts_IERC20.sol";
import {CollateralConfiguration} from "./CollateralConfiguration.sol";
import {Errors} from "./Errors.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {DataTypes} from "./DataTypes.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {IGuild} from "./IGuild.sol";
import {PerpetualDebtLogic} from "./PerpetualDebtLogic.sol";

import "./console.sol";

/**
 * @title GuildLogic library
 * @author Tazz Labs, inspired by AAVE v3
 * @notice Implements the logic for Guild specific functions
 */
library GuildLogic {
    using GPv2SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PerpetualDebtLogic for DataTypes.PerpetualDebtData;

    /**
     * @notice Initialize an asset collateral and add the collateral to the list of collaterals
     * @param collateralData The state of all the collaterals
     * @param collateralList The addresses of all the active collaterals
     * @param collateralCount Number of active collaterals
     * @param asset Collateral asset to be initialized
     * @return true if appended, false if inserted at existing empty spot
     **/
    function executeInitCollateral(
        mapping(address => DataTypes.CollateralData) storage collateralData,
        mapping(uint256 => address) storage collateralList,
        uint16 collateralCount,
        uint16 maxNumberCollaterals,
        address asset
    ) external returns (bool) {
        require(Address.isContract(asset), Errors.NOT_CONTRACT);

        bool collateralAlreadyAdded = collateralData[asset].id != 0 || collateralList[0] == asset;
        require(!collateralAlreadyAdded, Errors.COLLATERAL_ALREADY_ADDED);

        for (uint16 i = 0; i < collateralCount; i++) {
            if (collateralList[i] == address(0)) {
                collateralData[asset].id = i;
                collateralList[i] = asset;
                return false;
            }
        }

        require(collateralCount < maxNumberCollaterals, Errors.NO_MORE_COLLATERALS_ALLOWED);
        collateralData[asset].id = collateralCount;
        collateralList[collateralCount] = asset;
        return true;
    }

    /**
     * @notice Drop a collateral
     * @param collateralData The state of all the collaterals
     * @param collateralList The addresses of all the active collaterals
     * @param asset The address of the underlying collateral asset to be dropped
     **/
    function executeDropCollateral(
        mapping(address => DataTypes.CollateralData) storage collateralData,
        mapping(uint256 => address) storage collateralList,
        address asset
    ) internal {
        DataTypes.CollateralData storage collateral = collateralData[asset];
        //TODO
        //ValidationLogic.validateDropCollateral(collateralList, collateral, asset);
        collateralList[collateralData[asset].id] = address(0);
        delete collateralData[asset];
    }

    /**
     * @notice Returns the user account data across all the collaterals
     * @param collateralsData The state of all the collaterals
     * @param collateralsList The addresses of all the active collaterals
     * @param params Additional params needed for the calculation
     * @return userAccountData structured as IGuild.userAccountDataStruc with the following values
     * StrucParam: totalCollateralInBaseCurrency The total collateral of the user in the base currency used by the price feed
     * StrucParam:  totalDebtNotionalInBaseCurrency The total debt notional of the user in the base currency used by the price feed
     * StrucParam:  availableBorrowsInBaseCurrency The borrowing power left of the user in the base currency used by the price feed
     * StrucParam:  currentLiquidationThreshold The liquidation threshold of the user
     * StrucParam:  ltv The loan to value of The user
     * StrucParam:  healthFactor The current health factor of the user
     * StrucParam:  totalDebtNotional User's current debt notional
     * StrucParam:  availableBorrowsInZTokens The borrowing power left of the user in zTokens (base amount)
     * StrucParam:  availableNotionalBorrows The total notional that can be minted given borrowing capacity
     **/
    function executeGetUserAccountData(
        mapping(address => DataTypes.CollateralData) storage collateralsData,
        mapping(uint256 => address) storage collateralsList,
        DataTypes.PerpetualDebtData storage perpDebt,
        DataTypes.CalculateUserAccountDataParams memory params
    ) internal view returns (IGuild.userAccountDataStruc memory userAccountData) {
        (
            userAccountData.totalCollateralInBaseCurrency,
            userAccountData.totalDebtNotionalInBaseCurrency,
            userAccountData.ltv,
            userAccountData.currentLiquidationThreshold,
            userAccountData.healthFactor,

        ) = GenericLogic.calculateUserAccountData(collateralsData, collateralsList, perpDebt, params);

        (
            userAccountData.availableBorrowsInBaseCurrency,
            userAccountData.availableBorrowsInZTokens,
            userAccountData.availableNotionalBorrows
        ) = GenericLogic.calculateAvailableBorrows(
            userAccountData.totalCollateralInBaseCurrency,
            userAccountData.totalDebtNotionalInBaseCurrency,
            userAccountData.ltv,
            perpDebt,
            params
        );

        uint256 accountDebtBalance = perpDebt.getLiability().balanceOf(params.user);
        userAccountData.totalDebtNotional = perpDebt.getLiability().baseToNotional(accountDebtBalance);
        userAccountData.zTokensToRepayDebt = perpDebt.getAssetGivenLiability(accountDebtBalance);
    }
}

