// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IGuild} from "./IGuild.sol";

/**
 * @title ITazzHelper
 * @author Tazz Labs
 * @notice Defines the user interface for the TazzHelper function
 **/
interface ITazzHelper {
    /**
     * @dev Emitted on borrowMoney()
     * @param user The address of borrower
     * @param debtNotionalMintedInBaseCurrency The debt Notional minted (is 0 if only a swap)
     * @param zTokensIn The zTokens swapped
     * @param moneyOut The money obtained from swapping zTokens
     **/
    event MintAndSwap(
        address indexed user,
        uint256 debtNotionalMintedInBaseCurrency,
        uint256 zTokensIn,
        uint256 moneyOut
    );

    /**
     * @dev Emitted on repayMoney()
     * @param user The address of borrower
     * @param debtNotionalBurnedInBaseCurrency The debt Notional burned
     * @param moneyIn The zTokens burned (base)
     * @param zTokensOut The money swapped for the the zTokens that were burned
     **/
    event SwapAndBurn(
        address indexed user,
        uint256 debtNotionalBurnedInBaseCurrency,
        uint256 moneyIn,
        uint256 zTokensOut
    );

    /**
     * @notice Swaps zToken for money.  Mints zTokens if needed (and collateral is available)
     * @param _guildAddress The Guild we are minting debt from
     * @param _moneyOut The amount of money looking to swap debt for
     * @param _zTokenInMax The maximum zTokens we are willing to mint (in base amount)
     * @param _deadline The deadline timestamp after which the swap will not be accepted
     * @param _sqrtPriceLimitX96 Price limit of swap
     * @return debtNotionalMintedInBaseCurrency_ Debt notional minted for user in this transaction (in money decimal units)
     * @return zTokenIn_ Debt swapped for money in this transaction
     * @return moneyOut_ Money recieved from swap in this transaction
     * @dev Function swaps zTokens for exact money amount
     * @dev If user does not have enough zTokens, function will request Guild to mint missing zTokens
     * @dev This will be allowed, if user has enough collateral in Guild to mint zTokens
     * @dev Function over mints debt, and at the end cleans up by burning any unused (overminted) zTokens/debt.
     **/
    function swapZTokenForExactMoney(
        address _guildAddress,
        uint256 _moneyOut,
        uint256 _zTokenInMax,
        uint256 _deadline,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalMintedInBaseCurrency_,
            uint256 zTokenIn_,
            uint256 moneyOut_
        );

    /**
     * @notice Swaps money for zToken, and burns debt if it can
     * @param _guildAddress The Guild we are minting debt from
     * @param _zTokenOut The amount of zTokens we want out of this swap
     * @param _moneyInMax The maximum money we are willing to use
     * @param _deadline The deadline timestamp after which the swap will not be accepted
     * @param _sqrtPriceLimitX96 Price limit of swap
     * @return debtNotionalBurnedInBaseCurrency_ Debt notional burned for user in this transaction  (in money decimal units)
     * @return moneyIn_ Money swapped for zToken in this transaction
     * @return zTokenOut_ zToken recieved from swap in this transaction
     * @dev Function swaps zTokens for exact money amount
     * @dev If user does not have enough zTokens, function will request Guild to mint missing zTokens
     * @dev This will be allowed, if user has enough collateral in Guild to mint zTokens
     * @dev Function over mints debt, and at the end cleans up by burning any unused (overminted) zTokens/debt.
     **/
    function swapMoneyForExactZToken(
        address _guildAddress,
        uint256 _zTokenOut,
        uint256 _moneyInMax,
        uint256 _deadline,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalBurnedInBaseCurrency_,
            uint256 moneyIn_,
            uint256 zTokenOut_
        );

    /**
     * @notice Swaps money for zToken, and burns debt if it can
     * @param _guildAddress The Guild we are minting debt from
     * @param _moneyIn The amount of money used to repay debt
     * @param _zTokenOutMin money will be swapped for zTokens. This is the minimum amount of zTokens expected from the swap
     * @param _deadline The deadline timestamp after which the swap will not be accepted
     * @param _sqrtPriceLimitX96 Price limit of swap
     * @return debtNotionalBurnedInBaseCurrency_ Debt notional burned for user in this transaction  (in money decimal units)
     * @return moneyIn_ Money swapped for zToken in this transaction
     * @return zTokenOut_ zToken recieved from swap in this transaction
     * @dev Money from msg.sender is swapped for zTokens
     * @dev If msg.sender has debt, zTokens are used to burn as much debt as possible
     * @dev Excess zTokens are left in msg.senders wallet
     **/
    function swapExactMoneyForZToken(
        address _guildAddress,
        uint256 _moneyIn,
        uint256 _zTokenOutMin,
        uint256 _deadline,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalBurnedInBaseCurrency_,
            uint256 moneyIn_,
            uint256 zTokenOut_
        );

    /**
     * @notice Swaps zToken for money.  Mints zTokens if needed (and collateral is available)
     * @param _guildAddress The Guild we are minting debt from
     * @param _zTokenIn The amount of zTokens (base) swapped for money. If msg.sender does not have enough zTokens in their wallet, then zTokens are minted as new debt (if enough collateral)
     * @param _moneyOutMin zTokens will be swapped for money. This is the minimum amount of money expected from the swap
     * @param _deadline The deadline timestamp after which the swap will not be accepted
     * @param _sqrtPriceLimitX96 Price limit of swap
     * @return debtNotionalMintedInBaseCurrency_ Debt notional minted for user in this transaction  (in money decimal units)
     * @return zTokenIn_ Debt swapped for money in this transaction
     * @return moneyOut_ Money recieved from swap in this transaction
     **/
    function swapExactZTokenForMoney(
        address _guildAddress,
        uint256 _zTokenIn,
        uint256 _moneyOutMin,
        uint256 _deadline,
        uint160 _sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalMintedInBaseCurrency_,
            uint256 zTokenIn_,
            uint256 moneyOut_
        );

    /**
     * @notice calculates zToken swap for money.  Calculates zTokens that will be minted if needed (and collateral is available)
     * @dev They are also not gas efficient and should not be called on-chain.
     * @param guildAddress the guild address
     * @param moneyOutTarget The amount of money to receive after transaction
     * @param sqrtPriceLimitX96 Price limit of swap
     * @return debtNotionalMintedInBaseCurrency The amount of Debt Notional minted in users account to support transaction  (in money decimal units)
     * @return zTokenIn The amount of zToken required for transaction
     * @return moneyOut The amount of money received from swap
     * @return zTokenPriceBeforeSwap zToken price before the swap in money units
     * @return zTokenPriceAfterSwap zToken price after the swap in money units
     * @return gasEstimate The estimate of the gas that the swap consumes
     **/
    function quoteSwapZTokenForExactMoney(
        address guildAddress,
        uint256 moneyOutTarget,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalMintedInBaseCurrency,
            uint256 zTokenIn,
            uint256 moneyOut,
            uint256 zTokenPriceBeforeSwap,
            uint256 zTokenPriceAfterSwap,
            uint256 gasEstimate
        );

    /**
     * @notice calculates zToken swap for money.  Calculates zTokens that will be minted if needed (and collateral is available)
     * @dev They are also not gas efficient and should not be called on-chain.
     * @param guildAddress the guild address
     * @param zTokenInTarget The amount of zToken to swap for money in transaction
     * @param sqrtPriceLimitX96 Price limit of swap
     * @return debtNotionalMintedInBaseCurrency The amount of Debt Notional minted in users account to support transaction  (in money decimal units)
     * @return zTokenIn The amount of zToken required for transaction
     * @return moneyOut The amount of money received from swap
     * @return zTokenPriceBeforeSwap zToken price before the swap in money units
     * @return zTokenPriceAfterSwap zToken price after the swap in money units
     * @return gasEstimate The estimate of the gas that the swap consumes
     **/
    function quoteSwapExactZTokenForMoney(
        address guildAddress,
        uint256 zTokenInTarget,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalMintedInBaseCurrency,
            uint256 zTokenIn,
            uint256 moneyOut,
            uint256 zTokenPriceBeforeSwap,
            uint256 zTokenPriceAfterSwap,
            uint256 gasEstimate
        );

    /**
     * @notice quote for swapping money for zToken.  Calculates estimated debt that will be burned.
     * @dev They are also not gas efficient and should not be called on-chain.
     * @param guildAddress the guild address
     * @param moneyInTarget The amount of money to swap for zToken in transaction
     * @param sqrtPriceLimitX96 Price limit of swap
     * @return debtNotionalBurnedInBaseCurrency The amount of Debt Notional that is estimated will be burned after this transaction  (in money decimal units)
     * @return moneyIn The amount of money required for transaction
     * @return zTokenOut The amount of zToken received from swap
     * @return zTokenPriceBeforeSwap zToken price before the swap in money units
     * @return zTokenPriceAfterSwap zToken price after the swap in money units
     * @return gasEstimate The estimate of the gas that the swap consumes
     **/
    function quoteSwapExactMoneyForZToken(
        address guildAddress,
        uint256 moneyInTarget,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalBurnedInBaseCurrency,
            uint256 moneyIn,
            uint256 zTokenOut,
            uint256 zTokenPriceBeforeSwap,
            uint256 zTokenPriceAfterSwap,
            uint256 gasEstimate
        );

    /**
     * @notice quote for swapping money for zToken.  Calculates estimated debt that will be burned.
     * @dev They are also not gas efficient and should not be called on-chain.
     * @param guildAddress the guild address
     * @param zTokenOutTarget The amount of zTokens targeted after the swap (before being burned if debt is available)
     * @param sqrtPriceLimitX96 Price limit of swap
     * @return debtNotionalBurnedInBaseCurrency The amount of Debt Notional that is estimated will be burned after this transaction  (in money decimal units)
     * @return moneyIn The amount of money required for transaction
     * @return zTokenOut The amount of zToken received from swap
     * @return zTokenPriceBeforeSwap zToken price before the swap in money units
     * @return zTokenPriceAfterSwap zToken price after the swap in money units
     * @return gasEstimate The estimate of the gas that the swap consumes
     **/
    function quoteSwapMoneyForExactZToken(
        address guildAddress,
        uint256 zTokenOutTarget,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            uint256 debtNotionalBurnedInBaseCurrency,
            uint256 moneyIn,
            uint256 zTokenOut,
            uint256 zTokenPriceBeforeSwap,
            uint256 zTokenPriceAfterSwap,
            uint256 gasEstimate
        );

    /**
     * @notice Updates guild states (refinance) and then returns the user account data across all the collaterals
     * @dev This function is not gas efficient, and is meant to be called off-chain
     * @param guild The address of the guild
     * @param user The address of the user
     * @return userAccountData User variables as per IGuild.userAccountDataStruc structure with the following parameters
     * StrucParam: totalCollateralInBaseCurrency The total collateral of the user in the base currency used by the price feed
     * StrucParam: totalDebtNotionalInBaseCurrency The total debt of the user in the base currency used by the price feed
     * StrucParam: availableBorrowsInBaseCurrency The borrowing power left of the user in the base currency used by the price feed
     * StrucParam: currentLiquidationThreshold The liquidation threshold of the user
     * StrucParam: ltv The loan to value of The user
     * StrucParam: healthFactor The current health factor of the user
     * StrucParam: totalDebtNotional The total debt of the user in the native dToken decimal unit
     * StrucParam: availableBorrowsInZTokens The total zTokens that can be minted given borrowing capacity
     * StrucParam: availableNotionalBorrows The total notional that can be minted given borrowing capacity
     **/
    function quoteUserAccountData(address guild, address user)
        external
        returns (IGuild.userAccountDataStruc memory userAccountData);

    /**
     * @notice Returns the total money / ztokens in DEX placed as liquidity (irrespective of the actual price range it is placed at)
     * @param guild The address of the guild
     * @return moneyAmount amount of money tokens in DEX associated to Guild (in money units)
     * @return zTokenAmount amount of zTokens in DEX associated to Guild (in zToken units)
     **/
    function quoteDexLiquidty(address guild) external returns (uint256 moneyAmount, uint256 zTokenAmount);

    /**
     * @notice Returns the max amount of a collateral asset the user can deposit.  Validates whether that collateral is enabled.
     * @param guild The address of the guild
     * @param asset collateral asset to be deposited as collateral
     * @param amount amount of collateral to deposit
     * @return maxDepositAmount_ max amount that can be deposited.  Returns 0 if none (and/or reverts with validation errors)
     **/
    function quoteDeposit(
        address guild,
        address asset,
        uint256 amount
    ) external returns (uint256 maxDepositAmount_);

    /**
     * @notice Validates collateral withdrawal.  Returns current amount of that collateral in vault
     * @dev To check if the withdrawal can actually be made, an amount needs to be specified in the input.  This cannot be calculated a prior.
     * @dev The returned amount only indicates amount held by the Guild, and not how much can actually be withdrawn
     * @param guild The address of the guild
     * @param asset collateral asset to be deposited as collateral
     * @param amount amount of collateral to withdraw
     * @return currentCollateralInVault current collateral in Vault.  Returns 0 if none (and/or reverts with validation errors)
     **/
    function quoteWithdraw(
        address guild,
        address asset,
        uint256 amount
    ) external returns (uint256 currentCollateralInVault);

    /**
     * @notice Estimates max a user can deposit.  Analyzes business logic + returns errors if collateral is locked, etc.
     * @dev
     * @param guild The address of the guild
     * @param asset collateral asset to be deposited as collateral
     * @param user user that will deposit collateral
     * @return maxCollateralDeposit max amount that can be deposited.
     **/
    function quoteMaxDeposit(
        address guild,
        address asset,
        address user
    ) external returns (uint256 maxCollateralDeposit);

    /**
     * @notice Estimates max collateral a user can withdraw.  Analyzes business logic + returns errors if collateral is locked, etc.
     * @dev business logic included whether user's health goes < 1
     * @param guild The address of the guild
     * @param asset collateral asset to be deposited as collateral
     * @param user user that will deposit collateral
     * @return maxCollateralWithdraw max amount that can be withdrawn.
     **/
    function quoteMaxWithdaw(
        address guild,
        address asset,
        address user
    ) external returns (uint256 maxCollateralWithdraw);

    /**
     * @notice Estimates max ztoken in and money out for a swapZTokenForMoney call
     * @dev will analyze user debt mint capacity + dex liquidity
     * @param guild The address of the guild
     * @param user user that will be executing the swap
     * @param sqrtPriceLimitX96 Price limit of swap
     * @return maxFullZTokenIn max ztoken amount that can be taken in. This considers both zTokens currently in the wallet, as well as maximum debt account can take (ie, max new zTokens that can be minted)
     * @return maxFullMoneyOut max money amount that can be taken out. This considers both zTokens currently in the wallet, as well as maximum debt account can take (ie, max new zTokens that can be minted)
     * @return maxLimitZTokenIn max ztoken amount that can be taken in. This only considers zTokens in wallet both zTokens currently in the wallet (ie, postion closeout without new debt issued).
     * @return maxLimitMoneyOut max money amount that can be taken out.  This only considers zTokens in wallet both zTokens currently in the wallet (ie, postion closeout without new debt issued).
     **/
    function quoteMaxSwapZTokenForMoney(
        address guild,
        address user,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            uint256 maxFullZTokenIn,
            uint256 maxFullMoneyOut,
            uint256 maxLimitZTokenIn,
            uint256 maxLimitMoneyOut
        );

    /**
     * @notice Estimates max ztoken in and money out for a swapZTokenForMoney call
     * @dev will analyze user debt mint capacity + dex liquidity
     * @dev For 'Full', will calculate zTokens obtained from swapping all the money in users wallet for zTokens, only limited by sqrtPriceLimitX96.
     * @dev For 'Limit', will try and swap money in users wallet for zTokens, to cancel dToken amount, and also limited by sqrtPriceLimitX96.
     * @param guild The address of the guild
     * @param user   user that will be executing the swap
     * @param sqrtPriceLimitX96 Price limit of swap
     * @return maxFullMoneyIn max money amount that can be taken in.  This considers all money in the wallet, cancels existing debt, and issuance of new zTokens.
     * @return maxFullZTokenOut max zToken amount that can be taken out.   This considers all money in the wallet, cancels existing debt, and issuance of new zTokens.  The returned value are the amount of zTokens from the swap, before debt cancellation.
     * @return maxLimitMoneyIn max money amount that can be taken in.   This is limited by money in the wallet, and returns the money needed to repay debt (without buying zTokens with surplus)
     * @return maxLimitZTokenOut max zToken amount that can be taken out.   This is limited by money in the wallet, and returns the money needed to repay debt (without buying zTokens with surplus)
     **/
    function quoteMaxSwapMoneyForZToken(
        address guild,
        address user,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            uint256 maxFullMoneyIn,
            uint256 maxFullZTokenOut,
            uint256 maxLimitMoneyIn,
            uint256 maxLimitZTokenOut
        );

    /**
     * @notice Returns current price (slot0) for the DEX associated with Guild's zToken
     * @param guild The address of the guild
     * @return sqrtPriceX96_ Price limit of swap
     **/
    function quoteCurrentSqrtPriceX96(address guild) external view returns (uint160 sqrtPriceX96_);
}

