// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./Limiters.sol";
import "./ISavvyAdminActions.sol";
import "./ISavvyTokenParams.sol";

/// @title  IYieldStrategyManagerState
/// @author Savvy DeFi
interface IYieldStrategyManagerStates is ISavvyTokenParams {
    /// @notice Configures the the repay limit of `baseToken`.
    /// @param baseToken The address of the base token to configure the repay limit of.
    /// @param maximum         The maximum repay limit.
    /// @param blocks          The number of blocks it will take for the maximum repayment limit to be replenished when it is completely exhausted.
    function configureRepayLimit(
        address baseToken,
        uint256 maximum,
        uint256 blocks
    ) external;

    /// @notice Configure the repayWithCollateral limiter of `baseToken`.
    /// @param baseToken The address of the base token to configure the repayWithCollateral limit of.
    /// @param maximum         The maximum repayWithCollateral limit.
    /// @param blocks          The number of blocks it will take for the maximum repayWithCollateral limit to be replenished when it is completely exhausted.
    function configureRepayWithCollateralLimit(
        address baseToken,
        uint256 maximum,
        uint256 blocks
    ) external;

    /// @notice Configures the borrowing limiter.
    ///
    /// @param maximum The maximum borrowing limit.
    /// @param rate  The number of blocks it will take for the maximum borrowing limit to be replenished when it is completely exhausted.
    function configureBorrowingLimit(uint256 maximum, uint256 rate) external;

    /// @notice Sets the rate at which credit will be completely available to depositors after it is harvested.
    /// @param yieldToken The address of the yield token to set the credit unlock rate for.
    /// @param blocks     The number of blocks that it will take before the credit will be unlocked.
    function configureCreditUnlockRate(
        address yieldToken,
        uint256 blocks
    ) external;

    /// @notice Sets the maximum expected value of a yield token that the system can hold.
    ///
    /// @param yieldToken The address of the yield token to set the maximum expected value for.
    /// @param value      The maximum expected value of the yield token denoted measured in its base token.
    function setMaximumExpectedValue(
        address yieldToken,
        uint256 value
    ) external;

    /// @notice Sets the maximum loss that a yield bearing token will permit before restricting certain actions.
    /// @param yieldToken The address of the yield bearing token to set the maximum loss for.
    /// @param value      The value to set the maximum loss to. This is in units of basis points.
    function setMaximumLoss(address yieldToken, uint256 value) external;

    /// @notice Sets the token adapter of a yield token.
    /// @param yieldToken The address of the yield token to set the adapter for.
    /// @param adapter    The address to set the token adapter to.
    function setTokenAdapter(address yieldToken, address adapter) external;

    /// @notice Set the borrowing limiter.
    ///
    /// @notice `msg.sender` must be the admin or this call will revert with an {Unauthorized} error.
    ///
    /// @notice Emits a {BorrowingLimitUpdated} event.
    ///
    /// @param borrowingLimiter Limit information for borrowing.
    function setBorrowingLimiter(
        Limiters.LinearGrowthLimiter calldata borrowingLimiter
    ) external;

    /// @notice Set savvyPositionManager address.
    /// @dev Only owner can call this function.
    /// @param savvyPositionManager The address of savvyPositionManager.
    function setSavvyPositionManager(address savvyPositionManager) external;

    /// @notice Gets the conversion rate of base tokens per share.
    ///
    /// @param yieldToken The address of the yield token to get the conversion rate for.
    ///
    /// @return rate The rate of base tokens per share.
    function getBaseTokensPerShare(
        address yieldToken
    ) external view returns (uint256 rate);

    /// @notice Gets the conversion rate of yield tokens per share.
    ///
    /// @param yieldToken The address of the yield token to get the conversion rate for.
    ///
    /// @return rate The rate of yield tokens per share.
    function getYieldTokensPerShare(
        address yieldToken
    ) external view returns (uint256 rate);

    /// @notice Gets the supported base tokens.
    ///
    /// @dev The order of the entries returned by this function is not guaranteed to be consistent between calls.
    ///
    /// @return tokens The supported base tokens.
    function getSupportedBaseTokens()
        external
        view
        returns (address[] memory tokens);

    /// @notice Gets the supported yield tokens.
    ///
    /// @dev The order of the entries returned by this function is not guaranteed to be consistent between calls.
    ///
    /// @return tokens The supported yield tokens.
    function getSupportedYieldTokens()
        external
        view
        returns (address[] memory tokens);

    /// @notice Gets if an base token is supported.
    ///
    /// @param baseToken The address of the base token to check.
    ///
    /// @return isSupported If the base token is supported.
    function isSupportedBaseToken(
        address baseToken
    ) external view returns (bool isSupported);

    /// @notice Gets if a yield token is supported.
    ///
    /// @param yieldToken The address of the yield token to check.
    ///
    /// @return isSupported If the yield token is supported.
    function isSupportedYieldToken(
        address yieldToken
    ) external view returns (bool isSupported);

    /// @notice Gets the parameters of an base token.
    ///
    /// @param baseToken The address of the base token.
    ///
    /// @return params The base token parameters.
    function getBaseTokenParameters(
        address baseToken
    ) external view returns (BaseTokenParams memory params);

    /// @notice Get the parameters and state of a yield-token.
    ///
    /// @param yieldToken The address of the yield token.
    ///
    /// @return params The yield token parameters.
    function getYieldTokenParameters(
        address yieldToken
    ) external view returns (YieldTokenParams memory params);

    /// @notice Gets current limit, maximum, and rate of the borrowing limiter.
    ///
    /// @return currentLimit The current amount of debt tokens that can be borrowed.
    /// @return rate         The maximum possible amount of tokens that can be repaidWithCollateral at a time.
    /// @return maximum      The highest possible maximum amount of debt tokens that can be borrowed at a time.
    function getBorrowLimitInfo()
        external
        view
        returns (uint256 currentLimit, uint256 rate, uint256 maximum);

    /// @notice Gets current limit, maximum, and rate of a repay limiter for `baseToken`.
    ///
    /// @param baseToken The address of the base token.
    ///
    /// @return currentLimit The current amount of base tokens that can be repaid.
    /// @return rate         The rate at which the the current limit increases back to its maximum in tokens per block.
    /// @return maximum      The maximum possible amount of tokens that can be repaid at a time.
    function getRepayLimitInfo(
        address baseToken
    )
        external
        view
        returns (uint256 currentLimit, uint256 rate, uint256 maximum);

    /// @notice Gets current limit, maximum, and rate of the repayWithCollateral limiter for `baseToken`.
    ///
    /// @param baseToken The address of the base token.
    ///
    /// @return currentLimit The current amount of base tokens that can be repaid with Collateral.
    /// @return rate         The rate at which the function increases back to its maximum limit (tokens / block).
    /// @return maximum      The highest possible maximum amount of debt tokens that can be repaidWithCollateral at a time.
    function getRepayWithCollateralLimitInfo(
        address baseToken
    )
        external
        view
        returns (uint256 currentLimit, uint256 rate, uint256 maximum);

    /// @dev Gets the amount of shares that `amount` of `yieldToken` is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of yield tokens.
    ///
    /// @return The number of shares.
    function convertYieldTokensToShares(
        address yieldToken,
        uint256 amount
    ) external view returns (uint256);

    /// @dev Gets the amount of shares of `yieldToken` that `amount` of its base token is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of base tokens.
    ///
    /// @return The amount of shares.
    function convertBaseTokensToShares(
        address yieldToken,
        uint256 amount
    ) external view returns (uint256);

    /// @dev Gets the amount of yield tokens that `shares` shares of `yieldToken` is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param shares     The amount of shares.
    ///
    /// @return The amount of yield tokens.
    function convertSharesToYieldTokens(
        address yieldToken,
        uint256 shares
    ) external view returns (uint256);

    /// @dev Gets the amount of an base token that `amount` of `yieldToken` is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of yield tokens.
    ///
    /// @return The amount of base tokens.
    function convertYieldTokensToBaseToken(
        address yieldToken,
        uint256 amount
    ) external view returns (uint256);

    /// @dev Gets the amount of `yieldToken` that `amount` of its base token is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param amount     The amount of base tokens.
    ///
    /// @return The amount of yield tokens.
    function convertBaseTokensToYieldToken(
        address yieldToken,
        uint256 amount
    ) external view returns (uint256);

    /// @dev Gets the amount of base tokens that `shares` shares of `yieldToken` is exchangeable for.
    ///
    /// @param yieldToken The address of the yield token.
    /// @param shares     The amount of shares.
    ///
    /// @return baseToken           The address of base token.
    /// @return amountBaseTokens    The amount of base tokens.
    function convertSharesToBaseTokens(
        address yieldToken,
        uint256 shares
    ) external view returns (address baseToken, uint256 amountBaseTokens);

    /// @dev Calculates the amount of unlocked credit for `yieldToken` that is available for distribution.
    ///
    /// @param yieldToken The address of the yield token.
    ///
    /// @return currentAccruedWeight The current total accrued weight.
    /// @return unlockedCredit The amount of unlocked credit available.
    function calculateUnlockedCredit(
        address yieldToken
    )
        external
        view
        returns (uint256 currentAccruedWeight, uint256 unlockedCredit);

    /// @dev Gets the virtual active balance of `yieldToken`.
    ///
    /// @dev The virtual active balance is the active balance minus any harvestable tokens which have yet to be realized.
    ///
    /// @param yieldToken The address of the yield token to get the virtual active balance of.
    ///
    /// @return The virtual active balance.
    function calculateUnrealizedActiveBalance(
        address yieldToken
    ) external view returns (uint256);

    /// @notice Check token is supported by Savvy.
    /// @dev The token should not be yield token or base token that savvy contains.
    /// @dev If token is yield token or base token, reverts UnsupportedToken.
    /// @param rewardToken The address of token to check.
    function checkSupportTokens(address rewardToken) external view;

    /// @dev Checks if an address is a supported yield token.
    /// If the address is not a supported yield token, this function will revert using a {UnsupportedToken} error.
    /// @param yieldToken The address to check.
    function checkSupportedYieldToken(address yieldToken) external view;

    /// @dev Checks if an address is a supported base token.
    ///
    /// If the address is not a supported yield token, this function will revert using a {UnsupportedToken} error.
    ///
    /// @param baseToken The address to check.
    function checkSupportedBaseToken(address baseToken) external view;

    /// @notice Get repay limit information of baseToken.
    /// @param baseToken The address of base token.
    /// @return Repay limit information of baseToken.
    function repayLimiters(
        address baseToken
    ) external view returns (Limiters.LinearGrowthLimiter memory);

    /// @notice Get currnet borrow limit information.
    /// @return Current borrowing limit information.
    function currentBorrowingLimiter() external view returns (uint256);

    /// @notice Get current repay limit information of baseToken.
    /// @param baseToken The address of base token.
    /// @return Current repay limit information of baseToken.
    function currentRepayWithBaseTokenLimit(
        address baseToken
    ) external view returns (uint256);

    /// @notice Get current repayWithCollateral limit information of baseToken.
    /// @param baseToken The address of base token.
    /// @return Current repayWithCollateral limit information of baseToken.
    function currentRepayWithCollateralLimit(
        address baseToken
    ) external view returns (uint256);

    /// @notice Get repayWithCollateral limit information of baseToken.
    /// @param baseToken The address of base token.
    /// @return RepayWithCollateral limit information of baseToken.
    function repayWithCollateralLimiters(
        address baseToken
    ) external view returns (Limiters.LinearGrowthLimiter memory);

    /// @notice Get yield token parameter of yield token.
    /// @param yieldToken The address of yield token.
    /// @return The parameter of yield token.
    function getYieldTokenParams(
        address yieldToken
    ) external view returns (YieldTokenParams memory);

    /// @notice Check yield token loss is exceeds max loss.
    /// @dev If it's exceeds to max loss, revert `LossExceed(yieldToken, currentLoss, maximumLoss)`.
    /// @param yieldToken The address of yield token.
    function checkLoss(address yieldToken) external view;

    /// @notice Adds an base token to the system.
    /// @param debtToken The address of debt Token.
    /// @param baseToken The address of the base token to add.
    /// @param config          The initial base token configuration.
    function addBaseToken(
        address debtToken,
        address baseToken,
        ISavvyAdminActions.BaseTokenConfig calldata config
    ) external;

    /// @notice Adds a yield token to the system.
    /// @param yieldToken The address of the yield token to add.
    /// @param config     The initial yield token configuration.
    function addYieldToken(
        address yieldToken,
        ISavvyAdminActions.YieldTokenConfig calldata config
    ) external;

    /// @notice Sets an base token as either enabled or disabled.
    /// @param baseToken The address of the base token to enable or disable.
    /// @param enabled         If the base token should be enabled or disabled.
    function setBaseTokenEnabled(address baseToken, bool enabled) external;

    /// @notice Sets a yield token as either enabled or disabled.
    /// @param yieldToken The address of the yield token to enable or disable.
    /// @param enabled    If the base token should be enabled or disabled.
    function setYieldTokenEnabled(address yieldToken, bool enabled) external;

    /// @notice Get base token parameter of base token.
    /// @param baseToken The address of base token.
    /// @return The parameter of base token.
    function getBaseTokenParams(
        address baseToken
    ) external view returns (BaseTokenParams memory);

    /// @notice Get borrow limit information.
    /// @return Borrowing limit information.
    function borrowingLimiter()
        external
        view
        returns (Limiters.LinearGrowthLimiter memory);

    /// @notice Decrease borrowing limiter.
    /// @param amount The amount of borrowing to decrease.
    function decreaseBorrowingLimiter(uint256 amount) external;

    /// @notice Increase borrowing limiter.
    /// @param amount The amount of borrowing to increase.
    function increaseBorrowingLimiter(uint256 amount) external;

    /// @notice Decrease repayWithCollateral limiter.
    /// @param amount The amount of repayWithCollateral to decrease.
    function decreaseRepayWithCollateralLimiter(
        address baseToken,
        uint256 amount
    ) external;

    /// @notice Decrease base token repay limiter.
    /// @param amount The amount of base token repay to decrease.
    function decreaseRepayWithBaseTokenLimiter(
        address baseToken,
        uint256 amount
    ) external;
}

