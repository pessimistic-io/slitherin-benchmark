// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

/// @title  ISavvyErrors
/// @author Savvy DeFi
///
/// @notice Specifies errors.
interface ISavvyErrors {
    /// @notice An error which is used to indicate that an operation failed because it tried to operate on a token that the system did not recognize.
    ///
    /// @param token The address of the token.
    error UnsupportedToken(address token);

    /// @notice An error which is used to indicate that an operation failed because it tried to operate on a token that has been disabled.
    ///
    /// @param token The address of the token.
    error TokenDisabled(address token);

    /// @notice An error which is used to indicate that an operation failed because an account became undercollateralized.
    error Undercollateralized();

    /// @notice An error which is used to indicate that an operation failed because the expected value of a yield token in the system exceeds the maximum value permitted.
    ///
    /// @param yieldToken           The address of the yield token.
    /// @param expectedValue        The expected value measured in units of the base token.
    /// @param maximumExpectedValue The maximum expected value permitted measured in units of the base token.
    error ExpectedValueExceeded(
        address yieldToken,
        uint256 expectedValue,
        uint256 maximumExpectedValue
    );

    /// @notice An error which is used to indicate that an operation failed because the loss that a yield token in the system exceeds the maximum value permitted.
    ///
    /// @param yieldToken  The address of the yield token.
    /// @param loss        The amount of loss measured in basis points.
    /// @param maximumLoss The maximum amount of loss permitted measured in basis points.
    error LossExceeded(address yieldToken, uint256 loss, uint256 maximumLoss);

    /// @notice An error which is used to indicate that a borrowing operation failed because the borrowing limit has been exceeded.
    ///
    /// @param amount    The amount of debt tokens that were requested to be borrowed.
    /// @param available The amount of debt tokens which are available to borrow.
    error BorrowingLimitExceeded(uint256 amount, uint256 available);

    /// @notice An error which is used to indicate that an repay operation failed because the repay limit for an base token has been exceeded.
    ///
    /// @param baseToken The address of the base token.
    /// @param amount          The amount of base tokens that were requested to be repaid.
    /// @param available       The amount of base tokens that are available to be repaid.
    error RepayLimitExceeded(
        address baseToken,
        uint256 amount,
        uint256 available
    );

    /// @notice An error which is used to indicate that an repay operation failed because the repayWithCollateral limit for an base token has been exceeded.
    ///
    /// @param baseToken The address of the base token.
    /// @param amount          The amount of base tokens that were requested to be repaidWithCollateral.
    /// @param available       The amount of base tokens that are available to be repaidWithCollateral.
    error RepayWithCollateralLimitExceeded(
        address baseToken,
        uint256 amount,
        uint256 available
    );

    /// @notice An error which is used to indicate that the slippage of a wrap or unwrap operation was exceeded.
    ///
    /// @param amount           The amount of underlying or yield tokens returned by the operation.
    /// @param minimumAmountOut The minimum amount of the underlying or yield token that was expected when performing
    ///                         the operation.
    error SlippageExceeded(uint256 amount, uint256 minimumAmountOut);
}

library Errors {
    // TokenUtils
    string internal constant ERC20CALLFAILED_EXPECTDECIMALS = "SVY101";
    string internal constant ERC20CALLFAILED_SAFEBALANCEOF = "SVY102";
    string internal constant ERC20CALLFAILED_SAFETRANSFER = "SVY103";
    string internal constant ERC20CALLFAILED_SAFEAPPROVE = "SVY104";
    string internal constant ERC20CALLFAILED_SAFETRANSFERFROM = "SVY105";
    string internal constant ERC20CALLFAILED_SAFEMINT = "SVY106";
    string internal constant ERC20CALLFAILED_SAFEBURN = "SVY107";
    string internal constant ERC20CALLFAILED_SAFEBURNFROM = "SVY108";

    // SavvyPositionManager
    string internal constant SPM_FEE_EXCEEDS_BPS = "SVY201"; // protocol fee exceeds BPS
    string internal constant SPM_ZERO_ADMIN_ADDRESS = "SVY202"; // zero pending admin address
    string internal constant SPM_UNAUTHORIZED_PENDING_ADMIN = "SVY203"; // Unauthorized pending admin
    string internal constant SPM_ZERO_SAVVY_SAGE_ADDRESS = "SVY204"; // zero savvy sage address
    string internal constant SPM_ZERO_PROTOCOL_FEE_RECEIVER_ADDRESS = "SVY205"; // zero protocol fee receiver address
    string internal constant SPM_ZERO_RECIPIENT_ADDRESS = "SVY206"; // zero recipient address
    string internal constant SPM_ZERO_TOKEN_AMOUNT = "SVY207"; // zero token amount
    string internal constant SPM_INVALID_DEBT_AMOUNT = "SVY208"; // invalid debt amount
    string internal constant SPM_ZERO_COLLATERAL_AMOUNT = "SVY209"; // zero collateral amount
    string internal constant SPM_INVALID_UNREALIZED_DEBT_AMOUNT = "SVY210"; // invalid unrealized debt amount
    string internal constant SPM_UNAUTHORIZED_ADMIN = "SVY211"; // Unauthorized admin
    string internal constant SPM_UNAUTHORIZED_REDLIST = "SVY212"; // Unauthorized redlist
    string internal constant SPM_UNAUTHORIZED_SENTINEL_OR_ADMIN = "SVY213"; // Unauthorized sentinel or admin
    string internal constant SPM_UNAUTHORIZED_KEEPER = "SVY214"; // Unauthorized keeper
    string internal constant SPM_BORROWING_LIMIT_EXCEEDED = "SVY215"; // Borrowing limit exceeded
    string internal constant SPM_INVALID_TOKEN_AMOUNT = "SVY216"; // invalid token amount
    string internal constant SPM_EXPECTED_VALUE_EXCEEDED = "SVY217"; // Expected Value exceeded
    string internal constant SPM_SLIPPAGE_EXCEEDED = "SVY218"; // Slippage exceeded
    string internal constant SPM_UNDERCOLLATERALIZED = "SVY219"; // Undercollateralized
    string internal constant SPM_UNAUTHORIZED_NOT_ALLOWLISTED = "SVY220"; // Unathorized, not allowlisted
}

