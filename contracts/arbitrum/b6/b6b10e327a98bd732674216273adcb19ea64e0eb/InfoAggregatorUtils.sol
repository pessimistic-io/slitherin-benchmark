// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./ISavvyPositionManager.sol";
import "./ISavvyPriceFeed.sol";
import "./ISavvyInfoAggregatorStructs.sol";
import "./ITokenAdapter.sol";
import "./SafeCast.sol";
import "./TokenUtils.sol";
import "./Math.sol";

/**
 * @notice A library which implements fixed point decimal math.
 */
library InfoAggregatorUtils {
    uint256 public constant FIXED_POINT_SCALAR = 1e18;
    uint256 private constant OFFSET_RANGE = 100;

    function _convertDebtToUSD(
        int256 totalDebt,
        ISavvyPriceFeed svyPriceFeed_,
        ISavvyPositionManager savvyPositionManager_
    ) internal view returns (uint256) {
        uint256 actualDebt = SafeCast.toUint256(totalDebt);
        IYieldStrategyManager yieldStrategyManager = savvyPositionManager_
            .yieldStrategyManager();
        address[] memory yieldTokens = yieldStrategyManager
            .getSupportedYieldTokens();

        if (yieldTokens.length == 0) {
            return 0;
        }

        address yieldToken = yieldTokens[0];
        ISavvyState.YieldTokenParams
            memory yieldTokenParams = yieldStrategyManager
                .getYieldTokenParameters(yieldToken);
        address baseToken = yieldTokenParams.baseToken;

        uint256 baseTokenAmount = _normalizeBaseTokensToDebt(
            savvyPositionManager_,
            baseToken,
            actualDebt
        );

        return _getBaseTokenPrice(svyPriceFeed_, baseToken, baseTokenAmount);
    }

    /// @dev Normalize `amount` of `baseToken` to a value which is comparable to units of the debt token.
    ///
    /// @param baseToken_ The address of the base token.
    /// @param amount_          The amount of the debt token.
    ///
    /// @return The normalized amount.
    function _normalizeBaseTokensToDebt(
        ISavvyPositionManager savvyPositionManager_,
        address baseToken_,
        uint256 amount_
    ) internal view returns (uint256) {
        IYieldStrategyManager yieldStrategyManager = savvyPositionManager_
            .yieldStrategyManager();
        ISavvyState.BaseTokenParams
            memory baseTokenParams = yieldStrategyManager
                .getBaseTokenParameters(baseToken_);
        return amount_ / baseTokenParams.conversionFactor;
    }

    /// @notice Get token price.
    /// @param baseToken_ The address of base token.
    /// @param amount_ The base token amount.
    /// @return Return token price as 1e18
    function _getBaseTokenPrice(
        ISavvyPriceFeed svyPriceFeed_,
        address baseToken_,
        uint256 amount_
    ) internal view returns (uint256) {
        return svyPriceFeed_.getBaseTokenPrice(baseToken_, amount_);
    }

    /// @notice Gets information for all Savvy pools.
    ///
    /// @notice `account_` must be a non-zero address
    /// or this call will revert with a {IllegalArgument} error.
    ///
    /// @param account_ The specific wallet to get information for.
    /// @return poolsInfo Information for all Savvy pools.
    function _getPoolsInfo(
        ISavvyPriceFeed svyPriceFeed,
        address[] memory savvyPositionManagers,
        address account_
    )
        internal
        view
        returns (ISavvyInfoAggregatorStructs.FullPoolInfo[] memory)
    {
        Checker.checkArgument(account_ != address(0), "zero account address");

        uint256 numOfSavvyPositionManagers = savvyPositionManagers.length;

        uint256 numOfYieldTokens = 0;
        for (uint256 i = 0; i < numOfSavvyPositionManagers; i++) {
            ISavvyPositionManager savvyPositionManager = ISavvyPositionManager(
                savvyPositionManagers[i]
            );
            IYieldStrategyManager yieldStrategyManager = IYieldStrategyManager(
                savvyPositionManager.yieldStrategyManager()
            );
            address[] memory yieldTokens = yieldStrategyManager
                .getSupportedYieldTokens();
            for (uint256 j = 0; j < yieldTokens.length; j++) {
                if (
                    yieldStrategyManager
                        .getYieldTokenParameters(yieldTokens[j])
                        .enabled
                ) {
                    numOfYieldTokens++;
                }
            }
        }

        ISavvyInfoAggregatorStructs.FullPoolInfo[]
            memory poolsInfo = new ISavvyInfoAggregatorStructs.FullPoolInfo[](
                numOfYieldTokens
            );
        uint256 poolsInfoIdx = 0;

        for (uint256 i = 0; i < numOfSavvyPositionManagers; i++) {
            ISavvyPositionManager savvyPositionManager = ISavvyPositionManager(
                savvyPositionManagers[i]
            );
            IYieldStrategyManager yieldStrategyManager = IYieldStrategyManager(
                savvyPositionManager.yieldStrategyManager()
            );
            address[] memory supportedYieldTokens = yieldStrategyManager
                .getSupportedYieldTokens();
            ISavvyPriceFeed priceFeed = svyPriceFeed;
            for (uint256 j = 0; j < supportedYieldTokens.length; j++) {
                address yieldToken = supportedYieldTokens[j];
                ISavvyState.YieldTokenParams
                    memory yieldTokenParams = yieldStrategyManager
                        .getYieldTokenParameters(yieldToken);
                if (!yieldTokenParams.enabled) {
                    continue;
                }

                ISavvyInfoAggregatorStructs.FullSavvyPosition
                    memory poolDepositedInfo = _getFullDepositedTokenPosition(
                        account_,
                        yieldToken,
                        savvyPositionManager,
                        yieldStrategyManager,
                        priceFeed
                    );

                ISavvyState.BaseTokenParams
                    memory baseTokenParams = yieldStrategyManager
                        .getBaseTokenParameters(poolDepositedInfo.token);
                if (!baseTokenParams.enabled) {
                    continue;
                }

                poolsInfo[poolsInfoIdx] = ISavvyInfoAggregatorStructs
                    .FullPoolInfo(
                        address(savvyPositionManager), // savvyPositionManager
                        yieldToken, // poolAddress
                        poolDepositedInfo.token, // baseTokenAddress
                        poolDepositedInfo.amount, // userDepositedAmount
                        poolDepositedInfo.valueUSD, // userDepositedValueUSD
                        yieldTokenParams.expectedValue *
                            baseTokenParams.conversionFactor, // poolDepositedAmount
                        _getBaseTokenPrice(
                            priceFeed,
                            poolDepositedInfo.token,
                            yieldTokenParams.expectedValue
                        ), // poolDepositedValueUSD
                        yieldTokenParams.maximumExpectedValue *
                            baseTokenParams.conversionFactor, // maxPoolDepositedAmount
                        _getBaseTokenPrice(
                            priceFeed,
                            poolDepositedInfo.token,
                            yieldTokenParams.maximumExpectedValue
                        ), // maxPoolDepositedValueUSD,
                        0, // maxWithdrawableShares
                        0 // maxWithdrawableAmount
                    );
                poolsInfoIdx++;
            }
        }

        poolsInfoIdx = 0;
        for (uint256 i = 0; i < numOfSavvyPositionManagers; i++) {
            ISavvyPositionManager savvyPositionManager = ISavvyPositionManager(
                savvyPositionManagers[i]
            );
            IYieldStrategyManager yieldStrategyManager = IYieldStrategyManager(
                savvyPositionManager.yieldStrategyManager()
            );

            ISavvyInfoAggregatorStructs.SavvyWithdrawInfo[]
                memory withdrawableShares = _getWithdrawableAmount(
                    account_,
                    savvyPositionManager
                );
            address[] memory supportedYieldTokens = yieldStrategyManager
                .getSupportedYieldTokens();
            for (uint256 j = 0; j < supportedYieldTokens.length; j++) {
                address yieldToken = supportedYieldTokens[j];
                if (
                    !yieldStrategyManager
                        .getYieldTokenParameters(yieldToken)
                        .enabled
                ) {
                    continue;
                }
                ISavvyInfoAggregatorStructs.SavvyWithdrawInfo
                    memory savvyWithdrawInfo = _findWithdrawSharesForYieldToken(
                        yieldToken,
                        withdrawableShares
                    );

                poolsInfo[poolsInfoIdx]
                    .maxWithdrawableAmount = savvyWithdrawInfo.amount;
                poolsInfo[poolsInfoIdx]
                    .maxWithdrawableShares = savvyWithdrawInfo.shares;
                poolsInfoIdx++;
            }
        }

        return poolsInfo;
    }

    function _findWithdrawSharesForYieldToken(
        address yieldToken,
        ISavvyInfoAggregatorStructs.SavvyWithdrawInfo[]
            memory withdrawableShares
    )
        internal
        pure
        returns (ISavvyInfoAggregatorStructs.SavvyWithdrawInfo memory)
    {
        uint256 length = withdrawableShares.length;
        for (uint256 i = 0; i < length; i++) {
            if (yieldToken == withdrawableShares[i].yieldToken) {
                return withdrawableShares[i];
            }
        }

        return
            ISavvyInfoAggregatorStructs.SavvyWithdrawInfo(
                address(0),
                address(0),
                0,
                0
            );
    }

    /// @notice Get the FullSavvyPosition for the deposited
    /// token for an `account_`. For example, if a user
    /// used Savvy to deposit 1000 DAI into a beefy/curve
    /// strategy, the balance of the deposited token for the
    /// av3CRV `yieldToken_` would be 1000.
    ///
    /// @notice `yieldToken_` must be a valid yield token for the
    /// provided `savvyPositionManager_` or this call will revert
    /// with a {IllegalArgument} error.
    ///
    /// @param account_ The account's wallet to check.
    /// @param yieldToken_ The address of the yield token.
    /// @param savvyPositionManager_ The SavvyPositionManager
    /// that manages the deposits.
    /// @param yieldStrategyManager_ The YieldStrategyManager associtated
    /// with `savvyPositionManager_`.
    /// @return fullDepositedTokenPosition The balance and value of
    /// the base token deposited in Savvy.
    function _getFullDepositedTokenPosition(
        address account_,
        address yieldToken_,
        ISavvyPositionManager savvyPositionManager_,
        IYieldStrategyManager yieldStrategyManager_,
        ISavvyPriceFeed savvyPriceFeed_
    )
        internal
        view
        returns (ISavvyInfoAggregatorStructs.FullSavvyPosition memory)
    {
        Checker.checkArgument(
            yieldStrategyManager_.isSupportedYieldToken(yieldToken_),
            "unsupported yield token"
        );

        (uint256 shares, , ) = savvyPositionManager_.positions(
            account_,
            yieldToken_
        );

        (address baseToken, uint256 baseTokenAmount) = yieldStrategyManager_.convertSharesToBaseTokens(yieldToken_, shares);
        uint256 valueUSD = _getBaseTokenPrice(
            savvyPriceFeed_,
            baseToken,
            baseTokenAmount
        );

        ISavvyState.BaseTokenParams
            memory baseTokenParams = yieldStrategyManager_
                .getBaseTokenParams(baseToken);
        uint256 normalizedBaseTokenAmount = baseTokenAmount * baseTokenParams.conversionFactor;

        return
            ISavvyInfoAggregatorStructs.FullSavvyPosition(
                baseToken,
                normalizedBaseTokenAmount,
                valueUSD
            );
    }

    /// @notice Get the total deposited amount for `account_` across
    /// all suported tokens in `savvyPositionManager_`.
    /// @param account_ The account's wallet to check.
    /// @param savvyPositionManager_ The SavvyPositionManager
    /// that manages the deposits.
    /// @param yieldStrategyManager_ The YieldStrategyManager associtated
    /// with `savvyPositionManager_`.
    /// @return totalDepositedAmount The total amount of deposits
    /// across all supported tokens.
    function _getDepositedAmountForAccount(
        address account_,
        ISavvyPositionManager savvyPositionManager_,
        IYieldStrategyManager yieldStrategyManager_
    ) internal view returns (uint256) {
        address[] memory yieldTokens = yieldStrategyManager_
            .getSupportedYieldTokens();

        uint256 totalDepositedAmount = 0;
        for (uint256 i = 0; i < yieldTokens.length; i++) {
            address yieldToken = yieldTokens[i];
            (uint256 shares, , ) = savvyPositionManager_.positions(
                account_,
                yieldToken
            );

            ISavvyState.YieldTokenParams
                memory yieldTokenParams = yieldStrategyManager_
                    .getYieldTokenParameters(yieldToken);
            uint256 pricePerShare = ITokenAdapter(yieldTokenParams.adapter)
                .price();

            uint8 yieldTokenDecimals = TokenUtils.expectDecimals(yieldToken);
            uint256 baseTokenAmount = ((pricePerShare * shares) /
                10 ** yieldTokenDecimals);
            totalDepositedAmount += baseTokenAmount;
        }

        return totalDepositedAmount;
    }

    /// @notice Get the FullSavvyPosition for the outstanding
    /// debt for an `account_`. For example, if a user
    /// deposited 1000 DAI and borrowed 400 svUSD the user's
    /// outstanding debt would be the 400 svUSD. It is important
    /// to note that the balance of svUSD in a user's wallet
    /// has no bearing on the outstanding debt. If the user swaps
    /// the 400 svUSD for some stable token, they still owe 400 svUSD,
    /// or eligible repayment, token to Savvy.
    /// @param account_ The account's wallet to check.
    /// @param savvyPositionManager_ The SavvyPositionManager
    /// that manages the debt.
    /// @return fullOutstandingDebtInfo The balance and value of
    /// the outstanding debt.
    function _getFullOutstandingDebtInfo(
        address account_,
        ISavvyPriceFeed savvyPriceFeed_,
        ISavvyPositionManager savvyPositionManager_
    ) internal view returns (ISavvyInfoAggregatorStructs.FullDebtInfo memory) {
        (int256 debtAmount, ) = savvyPositionManager_.accounts(account_);
        return
            ISavvyInfoAggregatorStructs.FullDebtInfo(
                address(savvyPositionManager_),
                debtAmount,
                _getUserDebtValueUSD(
                    savvyPriceFeed_,
                    savvyPositionManager_,
                    account_
                )
            );
    }

    /// @notice Return total amount of user borrowed with specific SavvyPositionManager.
    /// @param savvyPositionManager_ Handle of SavvyPositionManager.
    /// @param user_ The address of user to get total deposited amount.
    /// @return The amount of total deposited calculated by USD.
    function _getUserDebtValueUSD(
        ISavvyPriceFeed savvyPriceFeed_,
        ISavvyPositionManager savvyPositionManager_,
        address user_
    ) internal view returns (int256) {
        (int256 debt, ) = savvyPositionManager_.accounts(user_);
        int256 debtAmount = 0;

        if (debt > 0) {
            debtAmount += SafeCast.toInt256(
                _convertDebtToUSD(debt, savvyPriceFeed_, savvyPositionManager_)
            );
        }

        return debtAmount;
    }

    /// @notice Get the FullSavvyPosition for a debt token
    /// in an `account_`'s wallet. For example, the balance
    /// of svUSD in the `account_`'s wallet. This is not the
    /// same as the debt the `account_` owes to Savvy.
    /// @dev TODO(2022-12-15, ramsey) The USD value of the debt
    /// token is approximated from the price of the a base
    /// token. Since the debt token is soft pegged to the base
    /// token, this proxy value should be close enough.
    /// @param account_ The account's wallet to check.
    /// @param savvyPositionManager_ The SavvyPositionManager
    /// that manages the debt token.
    /// @return fullDebtTokenPosition The balance and value of
    /// the debt token in the `account_`'s wallet.
    function _getFullDebtTokenPosition(
        address account_,
        ISavvyPriceFeed svyPriceFeed_,
        ISavvyPositionManager savvyPositionManager_
    )
        internal
        view
        returns (ISavvyInfoAggregatorStructs.FullSavvyPosition memory)
    {
        address addressOfDebtToken = savvyPositionManager_.debtToken();
        uint256 balanceOfDebtToken = IERC20(addressOfDebtToken).balanceOf(
            account_
        );
        uint256 valueOfDebtTokenUSD = _convertDebtToUSD(
            SafeCast.toInt256(balanceOfDebtToken),
            svyPriceFeed_,
            savvyPositionManager_
        );

        return
            ISavvyInfoAggregatorStructs.FullSavvyPosition(
                addressOfDebtToken,
                balanceOfDebtToken,
                valueOfDebtTokenUSD
            );
    }

    /// @notice Get the FullSavvyPosition for the available
    /// credit for an `account_`. For example, if a user
    /// deposited 1000 DAI, they can borrow up to 500 svUSD.
    /// Assume the user goes on to borrow 200 svUSD, the
    /// available credit of svUSD is 300.
    /// @param account_ The account's wallet to check.
    /// @param savvyPositionManager_ The SavvyPositionManager
    /// that manages the credit line.
    /// @return fullAvailableCreditPosition The balance and value of
    /// the available credit.
    function _getFullAvailableCreditPosition(
        address account_,
        ISavvyPositionManager savvyPositionManager_,
        ISavvyPriceFeed savvyPriceFeed_
    )
        internal
        view
        returns (ISavvyInfoAggregatorStructs.FullSavvyPosition memory)
    {
        uint256 availableCreditAmount = _getBorrowableAmount(
            account_,
            savvyPositionManager_
        );
        uint256 availableCreditUSD = _convertDebtToUSD(
            SafeCast.toInt256(availableCreditAmount),
            savvyPriceFeed_,
            savvyPositionManager_
        );

        return
            ISavvyInfoAggregatorStructs.FullSavvyPosition(
                savvyPositionManager_.debtToken(),
                availableCreditAmount,
                availableCreditUSD
            );
    }

    /// @notice Return total amount of user deposited with specific SavvyPositionManager.
    /// @param savvyPositionManager_ Handle of SavvyPositionManager.
    /// @param user_ The address of user to get total deposited amount.
    /// @return The amount of total deposited calculated by USD.
    function _getUserDepositedAmount(
        ISavvyPositionManager savvyPositionManager_,
        ISavvyPriceFeed savvyPriceFeed_,
        address user_
    ) internal view returns (uint256) {
        (, address[] memory depositedTokens) = savvyPositionManager_.accounts(
            user_
        );

        uint256 length = depositedTokens.length;
        uint256 totalAmount = 0;
        IYieldStrategyManager yieldStrategyManager = savvyPositionManager_
            .yieldStrategyManager();

        ISavvyPriceFeed priceFeed = savvyPriceFeed_;
        for (uint256 i = 0; i < length; i++) {
            address yieldToken = depositedTokens[i];
            (uint256 shares, , ) = savvyPositionManager_.positions(
                user_,
                yieldToken
            );
            (address baseToken, uint256 baseTokenAmount) = yieldStrategyManager.convertSharesToBaseTokens(yieldToken, shares);
            uint256 price = _getBaseTokenPrice(
                priceFeed,
                baseToken,
                baseTokenAmount
            );

            totalAmount += price;
        }

        return totalAmount;
    }

    /// @notice Get total available credit of a specific user.
    /// @dev Calculated as [total deposit] / [minimumCollateralization] - [current balance]
    /// @param savvyPositionManager_ Handle of SavvyPositionManager.
    /// @param user_ The address of user to get total deposited amount.
    /// @return Total amount of available credit of a specific user, calculated by USD.
    function _getUserAvailableCreditUSD(
        ISavvyPositionManager savvyPositionManager_,
        ISavvyPriceFeed savvyPriceFeed_,
        address user_
    ) internal view returns (int256) {
        uint256 minCollateralization = savvyPositionManager_
            .minimumCollateralization();
        uint256 totalDepositedAmount = _getUserDepositedAmount(
            savvyPositionManager_,
            savvyPriceFeed_,
            user_
        );
        int256 currentBalance = _getUserDebtValueUSD(
            savvyPriceFeed_,
            savvyPositionManager_,
            user_
        );

        int256 creditAmount = SafeCast.toInt256(
            (totalDepositedAmount * FIXED_POINT_SCALAR) / minCollateralization
        );

        return creditAmount - currentBalance;
    }

    /// @notice Get total debt amount of specific savvyPositionManager.
    /// @param savvyPositionManager_ Handl of the savvyPositionManager.
    /// @return Total debt amount of specific savvyPositionManager.
    function _getTotalDebtAmount(
        ISavvyPositionManager savvyPositionManager_,
        ISavvyPriceFeed svyPriceFeed_
    ) internal view returns (int256) {
        int256 totalDebt = savvyPositionManager_.totalDebt();
        int256 debtAmount = 0;

        if (totalDebt > 0) {
            debtAmount += SafeCast.toInt256(
                _convertDebtToUSD(
                    totalDebt,
                    svyPriceFeed_,
                    savvyPositionManager_
                )
            );
        }

        return debtAmount;
    }

    /// @notice Get total deposited amount of specific savvyPositionManager.
    /// @param savvyPositionManager_ Handle of the savvyPositionManager.
    /// @return Total deposited amount of specific savvyPositionManager.
    function _getTotalDepositedAmount(
        ISavvyPositionManager savvyPositionManager_,
        ISavvyPriceFeed svyPriceFeed_
    ) internal view returns (uint256) {
        IYieldStrategyManager yieldStrategyManager = savvyPositionManager_
            .yieldStrategyManager();
        address[] memory yieldTokens = yieldStrategyManager
            .getSupportedYieldTokens();

        uint256 length = yieldTokens.length;
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < length; i++) {
            uint256 price = _getDepositedTokenPrice(
                yieldTokens[i],
                address(savvyPositionManager_),
                svyPriceFeed_
            );
            totalAmount += price;
        }

        return totalAmount;
    }

    /// @notice Get total available credit of a specific user.
    /// @dev Calculated as [total deposit] / [minimumCollateralization] - [current balance]
    /// @param savvyPositionManager_ Handle of SavvyPositionManager.
    /// @return Total amount of available credit of a specific user, calculated by USD.
    function _getAvailableCreditUSD(
        ISavvyPositionManager savvyPositionManager_,
        ISavvyPriceFeed svyPriceFeed_
    ) internal view returns (int256) {
        uint256 minCollateralization = savvyPositionManager_
            .minimumCollateralization();
        uint256 totalDepositedAmount = _getTotalDepositedAmount(
            savvyPositionManager_,
            svyPriceFeed_
        );
        int256 currentBalance = _getTotalDebtAmount(
            savvyPositionManager_,
            svyPriceFeed_
        );

        int256 creditAmount = SafeCast.toInt256(
            (totalDepositedAmount * FIXED_POINT_SCALAR) / minCollateralization
        );

        return creditAmount - currentBalance;
    }

    /// @notice Get usd amount deposited with the base token by the user.
    /// @param user_ The address of an user.
    /// @param yieldToken_ The address of an yield token.
    /// @param savvyPositionManager_ The address of a savvyPositionManager.
    /// @return USD amount.
    function _getUserDepositedTokenPrice(
        address user_,
        address yieldToken_,
        address savvyPositionManager_,
        ISavvyPriceFeed svyPriceFeed_
    ) internal view returns (uint256) {
        IYieldStrategyManager yieldStrategyManager = ISavvyPositionManager(
            savvyPositionManager_
        ).yieldStrategyManager();
        if (!yieldStrategyManager.isSupportedYieldToken(yieldToken_)) {
            return 0;
        }

        (uint256 shares, , ) = ISavvyPositionManager(savvyPositionManager_)
            .positions(user_, yieldToken_);

        ISavvyState.YieldTokenParams
            memory yieldTokenParams = yieldStrategyManager
                .getYieldTokenParameters(yieldToken_);
        uint256 pricePerShare = ITokenAdapter(yieldTokenParams.adapter).price();

        uint8 yieldTokenDecimals = TokenUtils.expectDecimals(yieldToken_);
        uint256 baseTokenAmount = ((pricePerShare * shares) /
            10 ** yieldTokenDecimals);
        address baseToken = yieldTokenParams.baseToken;
        uint256 price = _getBaseTokenPrice(
            svyPriceFeed_,
            baseToken,
            baseTokenAmount
        );

        return price;
    }

    /// @notice Get usd amount deposited with the base token by all users.
    /// @param yieldToken_ The address of an yield token.
    /// @param savvyPositionManager_ The address of a savvyPositionManager.
    /// @return USD amount.
    function _getDepositedTokenPrice(
        address yieldToken_,
        address savvyPositionManager_,
        ISavvyPriceFeed svyPriceFeed_
    ) internal view returns (uint256) {
        IYieldStrategyManager yieldStrategyManager = ISavvyPositionManager(
            savvyPositionManager_
        ).yieldStrategyManager();

        ISavvyState.YieldTokenParams
            memory yieldTokenParams = yieldStrategyManager
                .getYieldTokenParameters(yieldToken_);
        uint256 shares = yieldTokenParams.totalShares;
        uint256 pricePerShare = ITokenAdapter(yieldTokenParams.adapter).price();

        uint8 yieldTokenDecimals = TokenUtils.expectDecimals(yieldToken_);
        uint256 baseTokenAmount = ((pricePerShare * shares) /
            10 ** yieldTokenDecimals);
        address baseToken = yieldTokenParams.baseToken;
        uint8 baseTokeDecimals = TokenUtils.expectDecimals(baseToken);
        uint256 conversionFactor = 10**(18 - baseTokeDecimals);
        uint256 price = _getBaseTokenPrice(
            svyPriceFeed_,
            baseToken,
            baseTokenAmount / conversionFactor
        );

        return price;
    }

    /// @notice Check that yieldToken is added to support tokens before.
    /// @param yieldTokenAddress_ The address of a yield token.
    /// @return return bool if already added, if not, return false.
    function _checkSupportTokenExist(
        ISavvyInfoAggregatorStructs.SupportTokenInfo[] memory supportTokens,
        address yieldTokenAddress_
    ) internal pure returns (bool) {
        uint256 length = supportTokens.length;

        for (uint256 i = 0; i < length; i++) {
            if (supportTokens[i].yieldToken == yieldTokenAddress_) {
                return true;
            }
        }

        return false;
    }

    function _getWithdrawableAmount(
        address owner_,
        ISavvyPositionManager savvyPositionManager_
    )
        internal
        view
        returns (ISavvyInfoAggregatorStructs.SavvyWithdrawInfo[] memory)
    {
        address account = owner_;
        ISavvyPositionManager positionManager = savvyPositionManager_;
        IYieldStrategyManager strategyManager = positionManager
            .yieldStrategyManager();
        (int256 debt, address[] memory depositedTokens) = positionManager
            .accounts(account);
        uint256 length = depositedTokens.length;

        if (length == 0) {
            return new ISavvyInfoAggregatorStructs.SavvyWithdrawInfo[](0);
        }

        uint256 totalValue = _getTotalValue(
            account,
            depositedTokens,
            positionManager,
            strategyManager
        );
        uint256 minCollateralization = positionManager
            .minimumCollateralization();
        uint256 virtualDebt = debt <= 0 ? 0 : uint256(debt);

        bool withdrawable = true;
        if (virtualDebt > 0) {
            uint256 collateralization = (totalValue * FIXED_POINT_SCALAR) /
                virtualDebt;
            if (collateralization < minCollateralization) {
                withdrawable = false;
            }
        }

        uint256 withdrawableValue = !withdrawable
            ? 0
            : (totalValue -
                (minCollateralization * virtualDebt) /
                FIXED_POINT_SCALAR);
        if (withdrawableValue <= OFFSET_RANGE) {
            withdrawable = false;
        }

        withdrawableValue = !withdrawable ? 0 : withdrawableValue;

        return
            _getWithdrawableShares(
                length,
                withdrawableValue,
                account,
                depositedTokens,
                positionManager
            );
    }

    function _getWithdrawableShares(
        uint256 _length,
        uint256 _withdrawableValue,
        address _account,
        address[] memory _depositedTokens,
        ISavvyPositionManager _positionManager
    )
        internal
        view
        returns (ISavvyInfoAggregatorStructs.SavvyWithdrawInfo[] memory)
    {
        ISavvyInfoAggregatorStructs.SavvyWithdrawInfo[]
            memory withdrawInfos = new ISavvyInfoAggregatorStructs.SavvyWithdrawInfo[](
                _length
            );
        IYieldStrategyManager strategyManager = _positionManager
            .yieldStrategyManager();
        uint256 availableValue = _withdrawableValue;
        for (uint256 i = 0; i < _length; i++) {
            address yieldToken = _depositedTokens[i];
            withdrawInfos[i] = ISavvyInfoAggregatorStructs.SavvyWithdrawInfo(
                address(_positionManager),
                yieldToken,
                0,
                0
            );

            if (availableValue > 0) {
                ISavvyTokenParams.YieldTokenParams
                    memory yieldTokenParams = strategyManager
                        .getYieldTokenParams(yieldToken);
                address baseToken = yieldTokenParams.baseToken;
                (uint256 shares, , ) = _positionManager.positions(
                    _account,
                    yieldToken
                );
                (, uint256 amountBaseTokens) = strategyManager
                    .convertSharesToBaseTokens(yieldToken, shares);
                ISavvyTokenParams.BaseTokenParams
                    memory _baseToken = strategyManager.getBaseTokenParams(
                        baseToken
                    );
                uint256 value = amountBaseTokens * _baseToken.conversionFactor;
                uint256 withdrawableShares = Math.min(availableValue, value);
                withdrawInfos[i].amount = withdrawableShares;
                withdrawableShares = strategyManager.convertBaseTokensToShares(
                    yieldToken,
                    withdrawableShares / _baseToken.conversionFactor
                );
                withdrawInfos[i].shares = withdrawableShares;
            }
        }

        return withdrawInfos;
    }

    function _getTotalValue(
        address account_,
        address[] memory depositedTokens_,
        ISavvyPositionManager savvyPositionManager_,
        IYieldStrategyManager strategyManager_
    ) internal view returns (uint256 totalValue) {
        totalValue = 0;
        uint256 length = depositedTokens_.length;
        for (uint256 i = 0; i < length; i++) {
            address yieldToken = depositedTokens_[i];
            ISavvyTokenParams.YieldTokenParams
                memory yieldTokenParams = strategyManager_.getYieldTokenParams(
                    yieldToken
                );
            address baseToken = yieldTokenParams.baseToken;
            (uint256 shares, , ) = savvyPositionManager_.positions(
                account_,
                yieldToken
            );
            (, uint256 amountBaseTokens) = strategyManager_
                .convertSharesToBaseTokens(yieldToken, shares);

            ISavvyTokenParams.BaseTokenParams
                memory _baseToken = strategyManager_.getBaseTokenParams(
                    baseToken
                );
            totalValue += amountBaseTokens * _baseToken.conversionFactor;
        }
    }

    /// @notice Get the synthetic credit line for a SavvyPositionManager.
    /// @param owner_ The account to query the synthetic credit line for.
    /// @param savvyPositionManager_ SavvyPositionManager to borrow against.
    /// @return The amount of synthetic that a user can borrow.
    function _getBorrowableAmount(
        address owner_,
        ISavvyPositionManager savvyPositionManager_
    ) internal view returns (uint256) {
        IYieldStrategyManager strategyManager = savvyPositionManager_
            .yieldStrategyManager();
        uint256 borrowLimit = strategyManager.currentBorrowingLimiter();
        address account = owner_;
        (int256 debt, address[] memory depositedTokens) = savvyPositionManager_
            .accounts(account);
        if (depositedTokens.length == 0 || borrowLimit == 0) {
            return 0;
        }

        uint256 totalValue = _getTotalValue(
            account,
            depositedTokens,
            savvyPositionManager_,
            strategyManager
        );
        uint256 minCollateralization = savvyPositionManager_
            .minimumCollateralization();
        uint256 virtualDebt = debt <= 0 ? 0 : uint256(debt);

        if (virtualDebt > 0) {
            uint256 collateralization = (totalValue * FIXED_POINT_SCALAR) /
                virtualDebt;
            if (collateralization < minCollateralization) {
                return 0;
            }
        }

        uint256 borrowableAmount = ((totalValue -
            (minCollateralization * virtualDebt) /
            FIXED_POINT_SCALAR) * FIXED_POINT_SCALAR) / minCollateralization;
        borrowableAmount = debt < 0
            ? borrowableAmount + uint256(-1 * debt)
            : borrowableAmount;
        if (borrowableAmount <= OFFSET_RANGE) {
            return 0;
        }

        return Math.min(borrowableAmount, borrowLimit);
    }

    /// @notice Gets information for the Dashboard page.
    ///
    /// @notice `account_` must be a non-zero address
    /// or this call will revert with a {IllegalArgument} error.
    ///
    /// @param account_ The specific wallet to get information for.
    /// @return poolsInfo Information for the Dashboard page.
    function _getDashboardPageInfo(
        address[] memory savvyPositionManagers,
        address account_,
        ISavvyPriceFeed svyPriceFeed_
    )
        internal
        view
        returns (ISavvyInfoAggregatorStructs.DashboardPageInfo memory)
    {
        Checker.checkArgument(account_ != address(0), "zero account address");

        // [prework] find number of supported base tokens and initialize arrays for DashboardPageInfo.
        uint256 numOfSavvyPositionManagers = savvyPositionManagers.length;

        uint256 numOfBaseTokens = 0;
        for (uint256 i = 0; i < numOfSavvyPositionManagers; i++) {
            ISavvyPositionManager savvyPositionManager = ISavvyPositionManager(
                savvyPositionManagers[i]
            );
            IYieldStrategyManager yieldStrategyManager = IYieldStrategyManager(
                savvyPositionManager.yieldStrategyManager()
            );
            address[] memory supportedTokens = yieldStrategyManager
                .getSupportedBaseTokens();
            for (uint256 j = 0; j < supportedTokens.length; j++) {
                if (
                    yieldStrategyManager
                        .getBaseTokenParameters(supportedTokens[j])
                        .enabled
                ) {
                    numOfBaseTokens++;
                }
            }
        }

        ISavvyInfoAggregatorStructs.FullSavvyPosition[]
            memory debtTokens = new ISavvyInfoAggregatorStructs.FullSavvyPosition[](
                numOfSavvyPositionManagers
            );
        ISavvyInfoAggregatorStructs.FullSavvyPosition[]
            memory depositedTokens = new ISavvyInfoAggregatorStructs.FullSavvyPosition[](
                numOfBaseTokens
            );
        ISavvyInfoAggregatorStructs.FullSavvyPosition[]
            memory availableDeposit = new ISavvyInfoAggregatorStructs.FullSavvyPosition[](
                numOfBaseTokens
            );
        ISavvyInfoAggregatorStructs.FullSavvyPosition[]
            memory availableCredit = new ISavvyInfoAggregatorStructs.FullSavvyPosition[](
                numOfSavvyPositionManagers
            );
        ISavvyInfoAggregatorStructs.FullDebtInfo[]
            memory outstandingDebt = new ISavvyInfoAggregatorStructs.FullDebtInfo[](
                numOfSavvyPositionManagers
            );

        // [work] populate arrays for DashboardPageInfo.
        for (uint256 i = 0; i < numOfSavvyPositionManagers; i++) {
            ISavvyPositionManager savvyPositionManager = ISavvyPositionManager(
                savvyPositionManagers[i]
            );
            IYieldStrategyManager yieldStrategyManager = IYieldStrategyManager(
                savvyPositionManager.yieldStrategyManager()
            );

            debtTokens[i] = _getFullDebtTokenPosition(
                account_,
                svyPriceFeed_,
                savvyPositionManager
            );
            availableCredit[i] = _getFullAvailableCreditPosition(
                account_,
                savvyPositionManager,
                svyPriceFeed_
            );
            outstandingDebt[i] = _getFullOutstandingDebtInfo(
                account_,
                svyPriceFeed_,
                savvyPositionManager
            );

            address[] memory supportedYieldTokens = yieldStrategyManager
                .getSupportedYieldTokens();
            address account = account_;
            ISavvyPriceFeed priceFeed = svyPriceFeed_;
            for (uint256 j = 0; j < supportedYieldTokens.length; j++) {
                if (
                    !yieldStrategyManager
                        .getYieldTokenParameters(supportedYieldTokens[j])
                        .enabled
                ) {
                    continue;
                }
                ISavvyInfoAggregatorStructs.FullSavvyPosition
                    memory depositedTokenPosition = _getFullDepositedTokenPosition(
                        account,
                        supportedYieldTokens[j],
                        savvyPositionManager,
                        yieldStrategyManager,
                        priceFeed
                    );

                address baseTokenAddress = depositedTokenPosition.token;
                if (
                    !yieldStrategyManager
                        .getBaseTokenParameters(baseTokenAddress)
                        .enabled
                ) {
                    continue;
                }

                uint256 idx = _findIndexFromFullSavvyPositionArray(
                    depositedTokens,
                    baseTokenAddress
                );
                depositedTokens[idx].token = baseTokenAddress;
                depositedTokens[idx].amount += depositedTokenPosition.amount;
                depositedTokens[idx].valueUSD += depositedTokenPosition
                    .valueUSD;
            }
        }

        // (2022-12-15) moved into its own for loop to resolve stack too deep error.
        for (uint256 i = 0; i < numOfBaseTokens; i++) {
            address baseTokenAddress = depositedTokens[i].token;
            uint256 availableDepositAmount = IERC20(baseTokenAddress).balanceOf(
                account_
            );
            uint8 baseTokenDecimals = TokenUtils.expectDecimals(
                baseTokenAddress
            );
            uint256 conversionFactor = (10 ** (18 - baseTokenDecimals));
            availableDeposit[i].token = baseTokenAddress;
            availableDeposit[i].amount =
                availableDepositAmount *
                conversionFactor;
            availableDeposit[i].valueUSD = _getBaseTokenPrice(
                svyPriceFeed_,
                baseTokenAddress,
                availableDepositAmount
            );
        }
        // [format] create DashboardPageInfo.
        return
            ISavvyInfoAggregatorStructs.DashboardPageInfo(
                debtTokens,
                depositedTokens,
                availableDeposit,
                availableCredit,
                outstandingDebt
            );
    }

    /// @notice Finds the index of a token's address
    /// in a FullSavvyPosition array. If the token is not
    /// found, the function will return the first empty
    /// index in the array.
    /// @param arr The array to traverse.
    /// @param token The token address to look for.
    /// @return idx The index of the token or the first
    /// available index.
    function _findIndexFromFullSavvyPositionArray(
        ISavvyInfoAggregatorStructs.FullSavvyPosition[] memory arr,
        address token
    ) internal pure returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i].token == token || arr[i].token == address(0)) {
                return i;
            }
        }
        return arr.length - 1;
    }
}

