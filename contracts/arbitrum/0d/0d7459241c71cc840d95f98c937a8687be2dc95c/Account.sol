// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import { FixedPoint128 } from "./FixedPoint128.sol";
import { FullMath } from "./FullMath.sol";
import { SafeCast } from "./libraries_SafeCast.sol";

import { AddressHelper } from "./AddressHelper.sol";
import { CollateralDeposit } from "./CollateralDeposit.sol";
import { SignedFullMath } from "./SignedFullMath.sol";
import { SignedMath } from "./SignedMath.sol";
import { LiquidityPositionSet } from "./LiquidityPositionSet.sol";
import { LiquidityPosition } from "./LiquidityPosition.sol";
import { Protocol } from "./Protocol.sol";
import { VTokenPosition } from "./VTokenPosition.sol";
import { VTokenPositionSet } from "./VTokenPositionSet.sol";

import { IClearingHouseStructures } from "./IClearingHouseStructures.sol";
import { IClearingHouseEnums } from "./IClearingHouseEnums.sol";
import { IVQuote } from "./IVQuote.sol";
import { IVToken } from "./IVToken.sol";
import { IERC20 } from "./IERC20.sol";

/// @title Cross margined account functions
/// @dev This library is deployed and used as an external library by ClearingHouse contract.
library Account {
    using AddressHelper for address;
    using FullMath for uint256;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using SignedMath for int256;

    using Account for Account.Info;
    using CollateralDeposit for CollateralDeposit.Set;
    using LiquidityPositionSet for LiquidityPosition.Set;
    using Protocol for Protocol.Info;
    using VTokenPosition for VTokenPosition.Info;
    using VTokenPositionSet for VTokenPosition.Set;

    /// @notice account info for user
    /// @param owner specifies the account owner
    /// @param tokenPositions is set of all open token positions
    /// @param collateralDeposits is set of all deposits
    struct Info {
        uint96 id;
        address owner;
        VTokenPosition.Set tokenPositions;
        CollateralDeposit.Set collateralDeposits;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    /**
     *  Errors
     */

    /// @notice error to denote that there is not enough margin for the transaction to go through
    /// @param accountMarketValue shows the account market value after the transaction is executed
    /// @param totalRequiredMargin shows the total required margin after the transaction is executed
    error InvalidTransactionNotEnoughMargin(int256 accountMarketValue, int256 totalRequiredMargin);

    /// @notice error to denote that there is not enough profit during profit withdrawal
    /// @param totalProfit shows the value of positions at the time of execution after removing amount specified
    error InvalidTransactionNotEnoughProfit(int256 totalProfit);

    /// @notice error to denote that there is enough margin, hence the liquidation is invalid
    /// @param accountMarketValue shows the account market value before liquidation
    /// @param totalRequiredMargin shows the total required margin before liquidation
    error InvalidLiquidationAccountAboveWater(int256 accountMarketValue, int256 totalRequiredMargin);

    /// @notice error to denote that there are active ranges present during token liquidation, hence the liquidation is invalid
    /// @param poolId shows the poolId for which range is active
    error InvalidLiquidationActiveRangePresent(uint32 poolId);

    /// @notice denotes withdrawal of profit in settlement token
    /// @param accountId serial number of the account
    /// @param amount amount of profit withdrawn
    event ProfitUpdated(uint256 indexed accountId, int256 amount);

    /**
     *  Events
     */

    /// @notice denotes add or remove of margin
    /// @param accountId serial number of the account
    /// @param collateralId token in which margin is deposited
    /// @param amount amount of tokens deposited
    event MarginUpdated(uint256 indexed accountId, uint32 indexed collateralId, int256 amount, bool isSettleProfit);

    /// @notice denotes range position liquidation event
    /// @dev all range positions are liquidated and the current tokens inside the range are added in as token positions to the account
    /// @param accountId serial number of the account
    /// @param keeperAddress address of keeper who performed the liquidation
    /// @param liquidationFee total liquidation fee charged to the account
    /// @param keeperFee total liquidaiton fee paid to the keeper (positive only)
    /// @param insuranceFundFee total liquidaiton fee paid to the insurance fund (can be negative in case the account is not enought to cover the fee)
    event LiquidityPositionsLiquidated(
        uint256 indexed accountId,
        address indexed keeperAddress,
        int256 liquidationFee,
        int256 keeperFee,
        int256 insuranceFundFee,
        int256 accountMarketValueFinal
    );

    /// @notice denotes token position liquidation event
    /// @dev the selected token position is take from the current account and moved to liquidatorAccount at a discounted prive to current pool price
    /// @param accountId serial number of the account
    /// @param poolId id of the rage trade pool for whose position was liquidated
    /// @param keeperFee total liquidaiton fee paid to keeper
    /// @param insuranceFundFee total liquidaiton fee paid to the insurance fund (can be negative in case the account is not enough to cover the fee)
    event TokenPositionLiquidated(
        uint256 indexed accountId,
        uint32 indexed poolId,
        int256 keeperFee,
        int256 insuranceFundFee,
        int256 accountMarketValueFinal
    );

    /**
     *  External methods
     */

    /// @notice changes deposit balance of 'vToken' by 'amount'
    /// @param account account to deposit balance into
    /// @param collateralId collateral id of the token
    /// @param amount amount of token to deposit or withdraw
    /// @param protocol set of all constants and token addresses
    /// @param checkMargin true to check if margin is available else false
    function updateMargin(
        Account.Info storage account,
        uint32 collateralId,
        int256 amount,
        Protocol.Info storage protocol,
        bool checkMargin
    ) external {
        _updateMargin(account, collateralId, amount, protocol, checkMargin, false);
    }

    /// @notice updates 'amount' of profit generated in settlement token
    /// @param account account to remove profit from
    /// @param amount amount of profit(settlement token) to add/remove
    /// @param protocol set of all constants and token addresses
    /// @param checkMargin true to check if margin is available else false
    function updateProfit(
        Account.Info storage account,
        int256 amount,
        Protocol.Info storage protocol,
        bool checkMargin
    ) external {
        _updateProfit(account, amount, protocol, checkMargin);
    }

    function settleProfit(Account.Info storage account, Protocol.Info storage protocol) external {
        _settleProfit(account, protocol);
    }

    /// @notice swaps 'vToken' of token amount equal to 'swapParams.amount'
    /// @notice if vTokenAmount>0 then the swap is a long or close short and if vTokenAmount<0 then swap is a short or close long
    /// @notice isNotional specifies whether the amount represents token amount (false) or vQuote amount(true)
    /// @notice isPartialAllowed specifies whether to revert (false) or to execute a partial swap (true)
    /// @notice sqrtPriceLimit threshold sqrt price which if crossed then revert or execute partial swap
    /// @param account account to swap tokens for
    /// @param poolId id of the pool to swap tokens for
    /// @param swapParams parameters for the swap (Includes - amount, sqrtPriceLimit, isNotional, isPartialAllowed)
    /// @param protocol set of all constants and token addresses
    /// @param checkMargin true to check if margin is available else false
    /// @return vTokenAmountOut amount of vToken after swap (user receiving then +ve, user paying then -ve)
    /// @return vQuoteAmountOut amount of vQuote after swap (user receiving then +ve, user paying then -ve)
    function swapToken(
        Account.Info storage account,
        uint32 poolId,
        IClearingHouseStructures.SwapParams memory swapParams,
        Protocol.Info storage protocol,
        bool checkMargin
    ) external returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        // make a swap. vQuoteIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback and send to the pool
        (vTokenAmountOut, vQuoteAmountOut) = account.tokenPositions.swapToken(account.id, poolId, swapParams, protocol);

        if (swapParams.settleProfit) {
            account._settleProfit(protocol);
        }
        // after all the stuff, account should be above water
        if (checkMargin) account._checkIfMarginAvailable(true, protocol);
    }

    /// @notice changes range liquidity 'vToken' of market value equal to 'vTokenNotional'
    /// @notice if 'liquidityDelta'>0 then liquidity is added and if 'liquidityChange'<0 then liquidity is removed
    /// @notice the liquidity change is reverted if the sqrt price at the time of execution is beyond 'slippageToleranceBps' of 'sqrtPriceCurrent' supplied
    /// @notice whenever liquidity change is done the external token position is taken out. If 'closeTokenPosition' is true this is swapped out else it is added to the current token position
    /// @param account account to change liquidity
    /// @param poolId id of the rage trade pool
    /// @param liquidityChangeParams parameters including lower tick, upper tick, liquidity delta, sqrtPriceCurrent, slippageToleranceBps, closeTokenPosition, limit order type
    /// @param protocol set of all constants and token addresses
    function liquidityChange(
        Account.Info storage account,
        uint32 poolId,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams,
        Protocol.Info storage protocol,
        bool checkMargin
    )
        external
        returns (
            int256 vTokenAmountOut,
            int256 vQuoteAmountOut,
            uint256 notionalValueAbs
        )
    {
        // mint/burn tokens + fee + funding payment
        (vTokenAmountOut, vQuoteAmountOut) = account.tokenPositions.liquidityChange(
            account.id,
            poolId,
            liquidityChangeParams,
            protocol
        );

        if (liquidityChangeParams.settleProfit) {
            account._settleProfit(protocol);
        }
        // after all the stuff, account should be above water
        if (checkMargin) account._checkIfMarginAvailable(true, protocol);

        notionalValueAbs = protocol.getNotionalValue(poolId, vTokenAmountOut, vQuoteAmountOut);
    }

    /// @notice liquidates all range positions in case the account is under water
    ///     charges a liquidation fee to the account and pays partially to the insurance fund and rest to the keeper.
    /// @dev insurance fund covers the remaining fee if the account market value is not enough
    /// @param account account to liquidate
    /// @param protocol set of all constants and token addresses
    /// @return keeperFee amount of liquidation fee paid to keeper
    /// @return insuranceFundFee amount of liquidation fee paid to insurance fund
    /// @return accountMarketValue account market value before liquidation
    function liquidateLiquidityPositions(Account.Info storage account, Protocol.Info storage protocol)
        external
        returns (
            int256 keeperFee,
            int256 insuranceFundFee,
            int256 accountMarketValue
        )
    {
        // check basis maintanace margin
        int256 totalRequiredMargin;
        uint256 notionalAmountClosed;

        (accountMarketValue, totalRequiredMargin) = account._getAccountValueAndRequiredMargin(false, protocol);

        // check and revert if account is above water
        if (accountMarketValue > totalRequiredMargin) {
            revert InvalidLiquidationAccountAboveWater(accountMarketValue, totalRequiredMargin);
        }
        // liquidate all liquidity positions
        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(account.id, protocol);

        // compute liquidation fees
        (keeperFee, insuranceFundFee) = _computeLiquidationFees(
            accountMarketValue,
            notionalAmountClosed,
            true,
            protocol.liquidationParams
        );

        account._updateVQuoteBalance(-(keeperFee + insuranceFundFee));
    }

    /// @notice liquidates token position specified by 'poolId' in case account is underwater
    ///     charges a liquidation fee to the account and pays partially to the insurance fund and rest to the keeper.
    /// @dev closes position uptil a specified slippage threshold in protocol.liquidationParams
    /// @dev insurance fund covers the remaining fee if the account market value is not enough
    /// @dev if there is range position this reverts (liquidators are supposed to liquidate range positions first)
    /// @param account account to liquidate
    /// @param poolId id of the pool to liquidate
    /// @param protocol set of all constants and token addresses
    /// @return keeperFee amount of liquidation fee paid to keeper
    /// @return insuranceFundFee amount of liquidation fee paid to insurance fund
    function liquidateTokenPosition(
        Account.Info storage account,
        uint32 poolId,
        Protocol.Info storage protocol
    ) external returns (int256 keeperFee, int256 insuranceFundFee) {
        bool isPartialLiquidation;

        // check if there is range position and revert
        if (account.tokenPositions.isTokenRangeActive(poolId)) revert InvalidLiquidationActiveRangePresent(poolId);

        {
            (int256 accountMarketValue, int256 totalRequiredMargin) = account._getAccountValueAndRequiredMargin(
                false,
                protocol
            );

            // check and revert if account is above water
            if (accountMarketValue > totalRequiredMargin) {
                revert InvalidLiquidationAccountAboveWater(accountMarketValue, totalRequiredMargin);
            } else if (
                // check if account is underwater but within partial liquidation threshold
                accountMarketValue >
                totalRequiredMargin.mulDiv(protocol.liquidationParams.closeFactorMMThresholdBps, 1e4)
            ) {
                isPartialLiquidation = true;
            }
        }

        int256 tokensToTrade;
        {
            // get the net token position and tokensToTrade = -tokenPosition
            // since no ranges are supposed to be there so only tokenPosition is in vTokenPositionSet
            VTokenPosition.Info storage vTokenPosition = account.tokenPositions.getTokenPosition(poolId, false);
            tokensToTrade = -vTokenPosition.balance;
            uint256 tokenNotionalValue = tokensToTrade.absUint().mulDiv(
                protocol.getCachedVirtualTwapPriceX128(poolId),
                FixedPoint128.Q128
            );

            // check if the token position is less than a certain notional value
            // if so then liquidate the whole position even if partial liquidation is allowed
            // otherwise do partial liquidation
            if (isPartialLiquidation && tokenNotionalValue > protocol.liquidationParams.minNotionalLiquidatable) {
                tokensToTrade = tokensToTrade.mulDiv(protocol.liquidationParams.partialLiquidationCloseFactorBps, 1e4);
            }
        }

        int256 accountMarketValueFinal;
        {
            uint160 sqrtPriceLimit;
            {
                // calculate sqrt price limit based on slippage threshold
                uint160 sqrtTwapPrice = protocol.getVirtualTwapSqrtPriceX96(poolId);
                if (tokensToTrade > 0) {
                    sqrtPriceLimit = uint256(sqrtTwapPrice)
                        .mulDiv(1e4 + protocol.liquidationParams.liquidationSlippageSqrtToleranceBps, 1e4)
                        .toUint160();
                } else {
                    sqrtPriceLimit = uint256(sqrtTwapPrice)
                        .mulDiv(1e4 - protocol.liquidationParams.liquidationSlippageSqrtToleranceBps, 1e4)
                        .toUint160();
                }
            }

            // close position uptil sqrt price limit
            (, int256 vQuoteAmountSwapped) = account.tokenPositions.swapToken(
                account.id,
                poolId,
                IClearingHouseStructures.SwapParams({
                    amount: tokensToTrade,
                    sqrtPriceLimit: sqrtPriceLimit,
                    isNotional: false,
                    isPartialAllowed: true,
                    settleProfit: false
                }),
                protocol
            );

            // get the account market value after closing the position
            accountMarketValueFinal = account._getAccountValue(protocol);

            // compute liquidation fees
            (keeperFee, insuranceFundFee) = _computeLiquidationFees(
                accountMarketValueFinal,
                vQuoteAmountSwapped.absUint(),
                false,
                protocol.liquidationParams
            );
        }

        // deduct liquidation fees from account
        account._updateVQuoteBalance(-(keeperFee + insuranceFundFee));

        emit TokenPositionLiquidated(account.id, poolId, keeperFee, insuranceFundFee, accountMarketValueFinal);
    }

    /// @notice removes limit order based on the current price position (keeper call)
    /// @param account account to liquidate
    /// @param poolId id of the pool for the range
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param protocol platform constants
    function removeLimitOrder(
        Account.Info storage account,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper,
        uint256 limitOrderFee,
        Protocol.Info storage protocol
    ) external {
        account.tokenPositions.removeLimitOrder(account.id, poolId, tickLower, tickUpper, protocol);

        account._updateVQuoteBalance(-int256(limitOrderFee));
    }

    /**
     *  External view methods
     */

    /// @notice returns market value for the account positions based on current market conditions
    /// @param account account to check
    /// @param protocol set of all constants and token addresses
    /// @return accountPositionProfits total market value of all the positions (token ) and deposits
    function getAccountPositionProfits(Account.Info storage account, Protocol.Info storage protocol)
        external
        view
        returns (int256 accountPositionProfits)
    {
        return account._getAccountPositionProfits(protocol);
    }

    /// @notice returns market value and required margin for the account based on current market conditions
    /// @dev (In case requiredMargin < minRequiredMargin then requiredMargin = minRequiredMargin)
    /// @param account account to check
    /// @param isInitialMargin true to use initial margin factor and false to use maintainance margin factor for calcualtion of required margin
    /// @param protocol set of all constants and token addresses
    /// @return accountMarketValue total market value of all the positions (token ) and deposits
    /// @return totalRequiredMargin total margin required to keep the account above selected margin requirement (intial/maintainance)
    function getAccountValueAndRequiredMargin(
        Account.Info storage account,
        bool isInitialMargin,
        Protocol.Info storage protocol
    ) external view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        return account._getAccountValueAndRequiredMargin(isInitialMargin, protocol);
    }

    /// @notice checks if market value > required margin else revert with InvalidTransactionNotEnoughMargin
    /// @param account account to check
    /// @param isInitialMargin true to use initialMarginFactor and false to use maintainance margin factor for calcualtion of required margin
    /// @param protocol set of all constants and token addresses
    function checkIfMarginAvailable(
        Account.Info storage account,
        bool isInitialMargin,
        Protocol.Info storage protocol
    ) external view {
        (int256 accountMarketValue, int256 totalRequiredMargin) = account._getAccountValueAndRequiredMargin(
            isInitialMargin,
            protocol
        );
        if (accountMarketValue < totalRequiredMargin)
            revert InvalidTransactionNotEnoughMargin(accountMarketValue, totalRequiredMargin);
    }

    /// @notice checks if profit is available to withdraw settlement token (token value of all positions > 0) else revert with InvalidTransactionNotEnoughProfit
    /// @param account account to check
    /// @param protocol set of all constants and token addresses
    function checkIfProfitAvailable(Account.Info storage account, Protocol.Info storage protocol) external view {
        _checkIfProfitAvailable(account, protocol);
    }

    /// @notice gets information about all the collateral and positions in the account
    /// @param account ref to the account state
    /// @param protocol ref to the protocol state
    /// @return owner of the account
    /// @return vQuoteBalance amount of vQuote in the account
    /// @return collateralDeposits list of all the collateral amounts
    /// @return tokenPositions list of all the token and liquidity positions
    function getInfo(Account.Info storage account, Protocol.Info storage protocol)
        external
        view
        returns (
            address owner,
            int256 vQuoteBalance,
            IClearingHouseStructures.CollateralDepositView[] memory collateralDeposits,
            IClearingHouseStructures.VTokenPositionView[] memory tokenPositions
        )
    {
        owner = account.owner;
        collateralDeposits = account.collateralDeposits.getInfo(protocol);
        (vQuoteBalance, tokenPositions) = account.tokenPositions.getInfo();
    }

    /// @notice gets the net position of the account for a given pool
    /// @param account ref to the account state
    /// @param poolId id of the pool
    /// @param protocol ref to the protocol state
    /// @return netPosition net position of the account for the pool
    function getNetPosition(
        Account.Info storage account,
        uint32 poolId,
        Protocol.Info storage protocol
    ) external view returns (int256 netPosition) {
        return account.tokenPositions.getNetPosition(poolId, protocol);
    }

    /**
     *  Internal methods
     */

    function updateAccountPoolPrices(Account.Info storage account, Protocol.Info storage protocol) internal {
        account.tokenPositions.updateOpenPoolPrices(protocol);
    }

    /// @notice settles profit or loss for the account
    /// @param account ref to the account state
    /// @param protocol ref to the protocol state
    function _settleProfit(Account.Info storage account, Protocol.Info storage protocol) internal {
        int256 profits = account._getAccountPositionProfits(protocol);
        uint32 settlementCollateralId = AddressHelper.truncate(protocol.settlementToken);
        if (profits > 0) {
            account._updateProfit(-profits, protocol, false);
            account._updateMargin({
                collateralId: settlementCollateralId,
                amount: profits,
                protocol: protocol,
                checkMargin: false,
                isSettleProfit: true
            });
        } else if (profits < 0) {
            uint256 balance = account.collateralDeposits.getBalance(settlementCollateralId);
            uint256 profitAbsUint = uint256(-profits);
            uint256 balanceToUpdate = balance > profitAbsUint ? profitAbsUint : balance;
            if (balanceToUpdate > 0) {
                account._updateMargin({
                    collateralId: settlementCollateralId,
                    amount: -balanceToUpdate.toInt256(),
                    protocol: protocol,
                    checkMargin: false,
                    isSettleProfit: true
                });
                account._updateProfit(balanceToUpdate.toInt256(), protocol, false);
            }
        }
    }

    /// @notice updates 'amount' of profit generated in settlement token
    /// @param account account to remove profit from
    /// @param amount amount of profit(settlement token) to add/remove
    /// @param protocol set of all constants and token addresses
    /// @param checkMargin true to check if margin is available else false
    function _updateProfit(
        Account.Info storage account,
        int256 amount,
        Protocol.Info storage protocol,
        bool checkMargin
    ) internal {
        account._updateVQuoteBalance(amount);

        if (checkMargin && amount < 0) {
            account._checkIfProfitAvailable(protocol);
            account._checkIfMarginAvailable(true, protocol);
        }

        emit ProfitUpdated(account.id, amount);
    }

    /// @notice changes deposit balance of 'vToken' by 'amount'
    /// @param account account to deposit balance into
    /// @param collateralId collateral id of the token
    /// @param amount amount of token to deposit or withdraw
    /// @param protocol set of all constants and token addresses
    /// @param checkMargin true to check if margin is available else false
    function _updateMargin(
        Account.Info storage account,
        uint32 collateralId,
        int256 amount,
        Protocol.Info storage protocol,
        bool checkMargin,
        bool isSettleProfit
    ) internal {
        if (amount > 0) {
            account.collateralDeposits.increaseBalance(collateralId, uint256(amount));
        } else {
            account.collateralDeposits.decreaseBalance(collateralId, uint256(-amount));
            if (checkMargin) account._checkIfMarginAvailable(true, protocol);
        }

        emit MarginUpdated(account.id, collateralId, amount, isSettleProfit);
    }

    /// @notice updates the vQuote balance for 'account' by 'amount'
    /// @param account pointer to 'account' struct
    /// @param amount amount of balance to update
    /// @return balanceAdjustments vToken and vQuote balance changes of the account
    function _updateVQuoteBalance(Account.Info storage account, int256 amount)
        internal
        returns (IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments)
    {
        balanceAdjustments = IClearingHouseStructures.BalanceAdjustments(amount, 0, 0);
        account.tokenPositions.vQuoteBalance += balanceAdjustments.vQuoteIncrease;
    }

    /**
     *  Internal view methods
     */

    /// @notice ensures that the account has enough margin to cover the required margin
    /// @param account ref to the account state
    /// @param protocol ref to the protocol state
    function _checkIfMarginAvailable(
        Account.Info storage account,
        bool isInitialMargin,
        Protocol.Info storage protocol
    ) internal view {
        (int256 accountMarketValue, int256 totalRequiredMargin) = account._getAccountValueAndRequiredMargin(
            isInitialMargin,
            protocol
        );
        if (accountMarketValue < totalRequiredMargin)
            revert InvalidTransactionNotEnoughMargin(accountMarketValue, totalRequiredMargin);
    }

    /// @notice ensures that the account has non negative profit
    /// @param account ref to the account state
    /// @param protocol ref to the protocol state
    function _checkIfProfitAvailable(Account.Info storage account, Protocol.Info storage protocol) internal view {
        int256 totalPositionValue = account._getAccountPositionProfits(protocol);
        if (totalPositionValue < 0) revert InvalidTransactionNotEnoughProfit(totalPositionValue);
    }

    /// @notice gets the amount of account's position profits
    /// @param account ref to the account state
    /// @param protocol ref to the protocol state
    function _getAccountPositionProfits(Account.Info storage account, Protocol.Info storage protocol)
        internal
        view
        returns (int256 accountPositionProfits)
    {
        accountPositionProfits = account.tokenPositions.getAccountMarketValue(protocol);
    }

    /// @notice gets market value for the account based on current market conditions
    /// @param account ref to the account state
    /// @param protocol set of all constants and token addresses
    /// @return accountMarketValue total market value of all the positions (token ) and deposits
    function _getAccountValue(Account.Info storage account, Protocol.Info storage protocol)
        internal
        view
        returns (int256 accountMarketValue)
    {
        accountMarketValue = account._getAccountPositionProfits(protocol);
        accountMarketValue += account.collateralDeposits.marketValue(protocol);
        return (accountMarketValue);
    }

    /// @notice gets market value and req margin for the account based on current market conditions
    /// @param account ref to the account state
    /// @param isInitialMargin true to use initialMarginFactor and false to use maintainance margin factor for calcualtion of required margin
    /// @param protocol set of all constants and token addresses
    /// @return accountMarketValue total market value of all the positions (token) and deposits
    /// @return totalRequiredMargin total required margin for the account
    function _getAccountValueAndRequiredMargin(
        Account.Info storage account,
        bool isInitialMargin,
        Protocol.Info storage protocol
    ) internal view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        accountMarketValue = account._getAccountValue(protocol);

        totalRequiredMargin = account.tokenPositions.getRequiredMargin(isInitialMargin, protocol);
        if (!account.tokenPositions.isEmpty()) {
            totalRequiredMargin = totalRequiredMargin < int256(protocol.minRequiredMargin)
                ? int256(protocol.minRequiredMargin)
                : totalRequiredMargin;
        }
        return (accountMarketValue, totalRequiredMargin);
    }

    /// @notice checks if 'account' is initialized
    /// @param account pointer to 'account' struct
    function _isInitialized(Account.Info storage account) internal view returns (bool) {
        return !account.owner.isZero();
    }

    /**
     *  Internal pure methods
     */

    /// @notice computes keeper fee and insurance fund fee in case of liquidity position liquidation
    /// @dev keeperFee = liquidationFee*(1-insuranceFundFeeShare)
    /// @dev insuranceFundFee = accountMarketValue - keeperFee (if accountMarketValue is not enough to cover the fees) else insurancFundFee = liquidationFee - keeperFee
    /// @param accountMarketValue market value of account
    /// @param notionalAmountClosed notional value of position closed
    /// @param isRangeLiquidation - true for range liquidation and false for token liquidation
    /// @param liquidationParams parameters including insuranceFundFeeShareBps
    /// @return keeperFee map of vTokens allowed on the platform
    /// @return insuranceFundFee poolwrapper for token
    function _computeLiquidationFees(
        int256 accountMarketValue,
        uint256 notionalAmountClosed,
        bool isRangeLiquidation,
        IClearingHouseStructures.LiquidationParams memory liquidationParams
    ) internal pure returns (int256 keeperFee, int256 insuranceFundFee) {
        uint256 liquidationFee;

        if (isRangeLiquidation) {
            liquidationFee = notionalAmountClosed.mulDiv(liquidationParams.rangeLiquidationFeeFraction, 1e5);
            if (liquidationParams.maxRangeLiquidationFees < liquidationFee)
                liquidationFee = liquidationParams.maxRangeLiquidationFees;
        } else {
            liquidationFee = notionalAmountClosed.mulDiv(liquidationParams.tokenLiquidationFeeFraction, 1e5);
        }

        int256 liquidationFeeInt = liquidationFee.toInt256();

        keeperFee = liquidationFeeInt.mulDiv(1e4 - liquidationParams.insuranceFundFeeShareBps, 1e4);
        if (accountMarketValue - liquidationFeeInt < 0) {
            insuranceFundFee = accountMarketValue - keeperFee;
        } else {
            insuranceFundFee = liquidationFeeInt - keeperFee;
        }
    }
}

