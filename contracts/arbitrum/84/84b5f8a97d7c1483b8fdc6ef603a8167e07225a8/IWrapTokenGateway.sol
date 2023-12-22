// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title  IWrapTokenGateway
/// @author Savvy DeFi
interface IWrapTokenGateway {
    /// @notice Refreshes the wrapped ethereum ERC20 approval for an savvy contract.
    ///
    /// @param _savvyPositionManager The address of the savvy to refresh the allowance for.
    function refreshAllowance(address _savvyPositionManager) external;

    /// @notice Set zero allowance the wrapped ethereum ERC20 approval for an savvy contract.
    ///
    /// @param _savvyPositionManager The address of the savvy to set the allowance for.
    function removeAllowance(address _savvyPositionManager) external;

    /// @notice Takes ethereum, converts it to wrapped ethereum, and then deposits it into an savvy.
    ///
    /// See [ISavvyActions.depositUnderlying](./savvy/ISavvyActions.md#depositBaseToken) for more details.
    ///
    /// @param _savvyPositionManager        The address of the savvy to deposit wrapped ethereum into.
    /// @param _yieldToken       The yield token to deposit the wrapped ethereum as.
    /// @param _amount           The amount of ethereum to deposit.
    /// @param _recipient        The address which will receive the deposited yield tokens.
    /// @param _minimumAmountOut The minimum amount of yield tokens that are expected to be deposited to `recipient`.
    function depositBaseToken(
        address _savvyPositionManager,
        address _yieldToken,
        uint256 _amount,
        address _recipient,
        uint256 _minimumAmountOut
    ) external payable;

    /// @notice Withdraws a wrapped ethereum based yield token from an savvy, converts it to ethereum, and then
    ///         transfers it to the recipient.
    ///
    /// A withdraw approval on the savvy is required for this call to succeed.
    ///
    /// See [ISavvyActions.withdrawUnderlying](./savvy/ISavvyActions.md#withdrawBaseToken) for more details.
    ///
    /// @param _savvyPositionManager        The address of the savvy to withdraw wrapped ethereum from.
    /// @param _yieldToken       The address of the yield token to withdraw.
    /// @param _shares           The amount of shares to withdraw.
    /// @param _recipient        The address which will receive the ethereum.
    /// @param _minimumAmountOut The minimum amount of base tokens that are expected to be withdrawn to `recipient`.
    function withdrawBaseToken(
        address _savvyPositionManager,
        address _yieldToken,
        uint256 _shares,
        address _recipient,
        uint256 _minimumAmountOut
    ) external;

    /// @notice See [ISavvyActions.depositUnderlying](./savvy/ISavvyActions.md#repayWithBaseToken) for more details.
    ///
    /// @param _savvyPositionManager        The address of the savvy to deposit wrapped ethereum into.
    /// @param _recipient        The address which will receive the deposited yield tokens.
    /// @param _amount           The amount of ethereum to deposit.
    /// @return The amount of tokens that were repaid.
    function repayWithBaseToken(
        address _savvyPositionManager,
        address _recipient,
        uint256 _amount
    ) external payable returns (uint256);
}

