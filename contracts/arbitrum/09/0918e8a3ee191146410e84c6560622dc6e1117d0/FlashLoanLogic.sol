// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {SafeERC20} from "./SafeERC20.sol";
import {SafeCast} from "./SafeCast.sol";
import {IERC20} from "./IERC20.sol";
import {IYToken} from "./IYToken.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {IFlashLoanSimpleReceiver} from "./IFlashLoanSimpleReceiver.sol";
import {IPool} from "./IPool.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {UserConfiguration} from "./UserConfiguration.sol";
import {ReserveConfiguration} from "./ReserveConfiguration.sol";
import {Errors} from "./Errors.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {DataTypes} from "./DataTypes.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {BorrowLogic} from "./BorrowLogic.sol";
import {ReserveLogic} from "./ReserveLogic.sol";

/**
 * @title FlashLoanLogic library
 *
 * @notice Implements the logic for the flash loans
 */
library FlashLoanLogic {
    using ReserveLogic for DataTypes.ReserveCache;
    using ReserveLogic for DataTypes.ReserveData;
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeCast for uint256;

    // Helper struct for internal variables used in the `executeFlashLoan` function
    struct FlashLoanLocalVars {
        IFlashLoanReceiver receiver;
        uint256 i;
        address currentAsset;
        uint256 currentAmount;
        uint256[] totalPremiums;
        uint256 flashloanPremiumTotal;
        uint256 flashloanPremiumToProtocol;
    }

    /**
     * @notice Implements the flashloan feature that allow users to access liquidity of the pool for one transaction
     * as long as the amount taken plus fee is returned or debt is opened.
     * @dev For authorized flashborrowers the fee is waived
     * @dev At the end of the transaction the pool will pull amount borrowed + fee from the receiver,
     * if the receiver have not approved the pool the transaction will revert.
     * @dev Emits the `FlashLoan()` event
     * @param reservesData The state of all the reserves
     * @param reservesList The addresses of all the active reserves
     * @param userConfig The user configuration mapping that tracks the supplied/borrowed assets
     * @param params The additional parameters needed to execute the flashloan function
     */
    function executeFlashLoan(
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(uint256 => address) storage reservesList,
        mapping(address => DataTypes.ERC1155ReserveData) storage erc1155ReservesData,
        DataTypes.UserConfigurationMap storage userConfig,
        DataTypes.UserERC1155ConfigurationMap storage userERC1155Config,
        DataTypes.FlashloanParams memory params
    ) external {
        // The usual action flow (cache -> updateState -> validation -> changeState -> updateRates)
        // is altered to (validation -> user payload -> cache -> updateState -> changeState -> updateRates) for flashloans.
        // This is done to protect against reentrance and rate manipulation within the user specified payload.

        ValidationLogic.validateFlashloan(reservesData, params.assets, params.amounts);

        FlashLoanLocalVars memory vars;

        vars.totalPremiums = new uint256[](params.assets.length);

        vars.receiver = IFlashLoanReceiver(params.receiverAddress);
        (vars.flashloanPremiumTotal, vars.flashloanPremiumToProtocol) = params.isAuthorizedFlashBorrower
            ? (0, 0)
            : (params.flashLoanPremiumTotal, params.flashLoanPremiumToProtocol);

        for (vars.i = 0; vars.i < params.assets.length; vars.i++) {
            vars.currentAmount = params.amounts[vars.i];
            vars.totalPremiums[vars.i] =
                !params.createPosition[vars.i] ? vars.currentAmount.percentMul(vars.flashloanPremiumTotal) : 0;
            IYToken(reservesData[params.assets[vars.i]].yTokenAddress).transferUnderlyingTo(
                params.receiverAddress, vars.currentAmount
            );
        }

        require(
            vars.receiver.executeOperation(params.assets, params.amounts, vars.totalPremiums, msg.sender, params.params),
            Errors.INVALID_FLASHLOAN_EXECUTOR_RETURN
        );

        for (vars.i = 0; vars.i < params.assets.length; vars.i++) {
            vars.currentAsset = params.assets[vars.i];
            vars.currentAmount = params.amounts[vars.i];

            if (!params.createPosition[vars.i]) {
                _handleFlashLoanRepayment(
                    reservesData[vars.currentAsset],
                    DataTypes.FlashLoanRepaymentParams({
                        asset: vars.currentAsset,
                        receiverAddress: params.receiverAddress,
                        amount: vars.currentAmount,
                        totalPremium: vars.totalPremiums[vars.i],
                        flashLoanPremiumToProtocol: vars.flashloanPremiumToProtocol,
                        referralCode: params.referralCode
                    })
                );
            } else {
                // If the user chose to not return the funds, the system checks if there is enough collateral and
                // eventually opens a debt position
                BorrowLogic.executeBorrow(
                    reservesData,
                    reservesList,
                    erc1155ReservesData,
                    userConfig,
                    userERC1155Config,
                    DataTypes.ExecuteBorrowParams({
                        asset: vars.currentAsset,
                        user: msg.sender,
                        onBehalfOf: params.onBehalfOf,
                        amount: vars.currentAmount,
                        referralCode: params.referralCode,
                        releaseUnderlying: false,
                        reservesCount: params.reservesCount,
                        oracle: IPoolAddressesProvider(params.addressesProvider).getPriceOracle(),
                        priceOracleSentinel: IPoolAddressesProvider(params.addressesProvider).getPriceOracleSentinel()
                    })
                );
                // no premium is paid when taking on the flashloan as debt
                emit IPool.FlashLoan(
                    params.receiverAddress,
                    msg.sender,
                    vars.currentAsset,
                    vars.currentAmount,
                    true,
                    0,
                    params.referralCode
                );
            }
        }
    }

    /**
     * @notice Implements the simple flashloan feature that allow users to access liquidity of ONE reserve for one
     * transaction as long as the amount taken plus fee is returned.
     * @dev Does not waive fee for approved flashborrowers nor allow taking on debt instead of repaying to save gas
     * @dev At the end of the transaction the pool will pull amount borrowed + fee from the receiver,
     * if the receiver have not approved the pool the transaction will revert.
     * @dev Emits the `FlashLoan()` event
     * @param reserve The state of the flashloaned reserve
     * @param params The additional parameters needed to execute the simple flashloan function
     */
    function executeFlashLoanSimple(
        DataTypes.ReserveData storage reserve,
        DataTypes.FlashloanSimpleParams memory params
    ) external {
        // The usual action flow (cache -> updateState -> validation -> changeState -> updateRates)
        // is altered to (validation -> user payload -> cache -> updateState -> changeState -> updateRates) for flashloans.
        // This is done to protect against reentrance and rate manipulation within the user specified payload.

        ValidationLogic.validateFlashloanSimple(reserve);

        IFlashLoanSimpleReceiver receiver = IFlashLoanSimpleReceiver(params.receiverAddress);
        uint256 totalPremium = params.amount.percentMul(params.flashLoanPremiumTotal);
        IYToken(reserve.yTokenAddress).transferUnderlyingTo(params.receiverAddress, params.amount);

        require(
            receiver.executeOperation(params.asset, params.amount, totalPremium, msg.sender, params.params),
            Errors.INVALID_FLASHLOAN_EXECUTOR_RETURN
        );

        _handleFlashLoanRepayment(
            reserve,
            DataTypes.FlashLoanRepaymentParams({
                asset: params.asset,
                receiverAddress: params.receiverAddress,
                amount: params.amount,
                totalPremium: totalPremium,
                flashLoanPremiumToProtocol: params.flashLoanPremiumToProtocol,
                referralCode: params.referralCode
            })
        );
    }

    /**
     * @notice Handles repayment of flashloaned assets + premium
     * @dev Will pull the amount + premium from the receiver, so must have approved pool
     * @param reserve The state of the flashloaned reserve
     * @param params The additional parameters needed to execute the repayment function
     */
    function _handleFlashLoanRepayment(
        DataTypes.ReserveData storage reserve,
        DataTypes.FlashLoanRepaymentParams memory params
    ) internal {
        uint256 premiumToProtocol = params.totalPremium.percentMul(params.flashLoanPremiumToProtocol);
        uint256 premiumToLP = params.totalPremium - premiumToProtocol;
        uint256 amountPlusPremium = params.amount + params.totalPremium;

        DataTypes.ReserveCache memory reserveCache = reserve.cache();
        reserve.updateState(reserveCache);
        reserveCache.nextLiquidityIndex = reserve.cumulateToLiquidityIndex(
            IERC20(reserveCache.yTokenAddress).totalSupply()
                + uint256(reserve.accruedToTreasury).rayMul(reserveCache.nextLiquidityIndex),
            premiumToLP
        );

        reserve.accruedToTreasury += premiumToProtocol.rayDiv(reserveCache.nextLiquidityIndex).toUint128();

        reserve.updateInterestRates(reserveCache, params.asset, amountPlusPremium, 0);

        IERC20(params.asset).safeTransferFrom(params.receiverAddress, reserveCache.yTokenAddress, amountPlusPremium);

        IYToken(reserveCache.yTokenAddress).handleRepayment(
            params.receiverAddress, params.receiverAddress, amountPlusPremium
        );

        emit IPool.FlashLoan(
            params.receiverAddress,
            msg.sender,
            params.asset,
            params.amount,
            false,
            params.totalPremium,
            params.referralCode
        );
    }
}

