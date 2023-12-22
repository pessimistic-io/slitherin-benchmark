// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
pragma abicoder v2;

/// @title IAave proxy contract
/// @author Matin Kaboli
interface IAave {
    struct DepositParams {
        address token;
        uint256 amount;
        address recipient;
    }

    /// @notice Deposits a token to the lending pool V2 and transfers aTokens to recipient
    /// @param _params Supply parameters
    /// token Token to deposit
    /// amount Amount to deposit
    /// recipient Recipient of the deposit that will receive aTokens
    function depositV2(DepositParams calldata _params) external payable;

    /// @notice Deposits a token to the lending pool V3 and transfers aTokens to recipient
    /// @param _params Supply parameters
    /// token Token to deposit
    /// amount Amount to deposit
    /// recipient Recipient of the deposit that will receive aTokens
    function depositV3(DepositParams calldata _params) external payable;

    struct WithdrawParams {
        address token;
        uint256 amount;
        address recipient;
    }

    /// @notice Receives aToken and transfers ERC20 token to recipient using lending pool V2
    /// @param _params Withdraw params
    /// token Token to withdraw
    /// amount Amount to withdraw
    /// recipient Recipient to receive ERC20 tokens
    function withdrawV2(WithdrawParams calldata _params) external payable;

    /// @notice Receives aToken and transfers ERC20 token to recipient using lending pool V3
    /// @param _params Withdraw params
    /// token Token to withdraw
    /// amount Amount to withdraw
    /// recipient Recipient to receive ERC20 tokens
    function withdrawV3(WithdrawParams calldata _params) external payable;

    struct WithdrawETHParams {
        uint256 amount;
        address recipient;
    }

    /// @notice Receives A_WETH and transfers ETH token to recipient using lending pool V2
    /// @param _params Withdraw params
    /// amount Amount to withdraw
    /// recipient Recipient to receive ETH
    function withdrawETHV2(WithdrawETHParams calldata _params) external payable;

    /// @notice Receives A_WETH and transfers ETH token to recipient using lending pool V3
    /// @param _params Withdraw params
    /// amount Amount to withdraw
    /// recipient Recipient to receive ETH
    function withdrawETHV3(WithdrawETHParams calldata _params) external payable;

    struct RepayParams {
        address token;
        uint96 rateMode;
        uint256 amount;
        address recipient;
    }

    /// @notice Repays a borrowed token using lending pool V2
    /// @param _params Rate mode, 1 for stable and 2 for variable
    /// token Token to repay
    /// amount Amount to repay
    /// rateMode Rate mode, 1 for stable and 2 for variable
    /// recipient Recipient to repay for
    function repayV2(IAave.RepayParams calldata _params) external payable;

    /// @notice Repays a borrowed token using lending pool V3
    /// @param _params Rate mode, 1 for stable and 2 for variable
    /// token Token to repay
    /// amount Amount to repay
    /// rateMode Rate mode, 1 for stable and 2 for variable
    /// recipient Recipient to repay for
    function repayV3(IAave.RepayParams calldata _params) external payable;
}

