// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./ISavvyTokenParams.sol";
import "./IYieldStrategyManager.sol";
import "./Sets.sol";

/// @title  ISavvyState
/// @author Savvy DeFi
interface ISavvyState is ISavvyTokenParams {
    /// @notice A user account.
    struct Account {
        // A signed value which represents the current amount of debt or credit that the account has accrued.
        // Positive values indicate debt, negative values indicate credit.
        int256 debt;
        // The share balances for each yield token.
        mapping(address => uint256) balances;
        // The last values recorded for accrued weights for each yield token.
        mapping(address => uint256) lastAccruedWeights;
        // The set of yield tokens that the account has deposited into the system.
        Sets.AddressSet depositedTokens;
        // The allowances for borrows.
        mapping(address => uint256) borrowAllowances;
        // The allowances for withdrawals.
        mapping(address => mapping(address => uint256)) withdrawAllowances;
        // The harvested base token amount per yield token.
        mapping(address => uint256) harvestedYield;
    }

    /// @notice Gets the address of the admin.
    ///
    /// @return admin The admin address.
    function admin() external view returns (address admin);

    /// @notice The total number of debt token.
    /// @return totalDebt Total debt amount.
    function totalDebt() external view returns (int256 totalDebt);

    /// @notice Gets the address of the pending administrator.
    ///
    /// @return pendingAdmin The pending administrator address.
    function pendingAdmin() external view returns (address pendingAdmin);

    /// @notice Gets if an address is a sentinel.
    ///
    /// @param sentinel The address to check.
    ///
    /// @return isSentinel If the address is a sentinel.
    function sentinels(
        address sentinel
    ) external view returns (bool isSentinel);

    /// @notice Gets if an address is a keeper.
    ///
    /// @param keeper The address to check.
    ///
    /// @return isKeeper If the address is a keeper
    function keepers(address keeper) external view returns (bool isKeeper);

    /// @notice Gets the address of the savvySage.
    ///
    /// @return savvySage The savvySage address.
    function savvySage() external view returns (address savvySage);

    /// @notice Gets the address of the svyBooster.
    ///
    /// @return svyBooster The svyBooster address.
    function svyBooster() external view returns (address svyBooster);

    /// @notice Gets the minimum collateralization.
    ///
    /// @notice Collateralization is determined by taking the total value of collateral that a user has deposited into their account and dividing it their debt.
    ///
    /// @dev The value returned is a 18 decimal fixed point integer.
    ///
    /// @return minimumCollateralization The minimum collateralization.
    function minimumCollateralization()
        external
        view
        returns (uint256 minimumCollateralization);

    /// @notice Gets the protocol fee.
    ///
    /// @return protocolFee The protocol fee.
    function protocolFee() external view returns (uint256 protocolFee);

    /// @notice Gets the protocol fee receiver.
    ///
    /// @return protocolFeeReceiver The protocol fee receiver.
    function protocolFeeReceiver()
        external
        view
        returns (address protocolFeeReceiver);

    /// @notice Gets the address of the allowlist contract.
    ///
    /// @return allowlist The address of the allowlist contract.
    function allowlist() external view returns (address allowlist);

    /// @notice Gets value to present redlist is active or not.
    ///
    /// @return redlistActive The redlist is active.
    function redlistActive() external view returns (bool redlistActive);

    /// @notice Gets value to present protocolTokenRequire is active or not.
    ///
    /// @return protocolTokenRequired The protocolTokenRequired is active.
    function protocolTokenRequired()
        external
        view
        returns (bool protocolTokenRequired);

    /// @notice The address of WrapTokenGateway contract.
    ///
    /// @return wrapTokenGateway The address of WrapTokenGateway contract.
    function wrapTokenGateway()
        external
        view
        returns (address wrapTokenGateway);

    /// @notice Gets information about the account owned by `owner`.
    ///
    /// @param owner The address that owns the account.
    ///
    /// @return debt            The unrealized amount of debt that the account had incurred.
    /// @return depositedTokens The yield tokens that the owner has deposited.
    function accounts(
        address owner
    ) external view returns (int256 debt, address[] memory depositedTokens);

    /// @notice Gets information about a yield token position for the account owned by `owner`.
    ///
    /// @param owner      The address that owns the account.
    /// @param yieldToken The address of the yield token to get the position of.
    ///
    /// @return shares            The amount of shares of that `owner` owns of the yield token.
    /// @return harvestedYield    The amount of harvested yield.
    /// @return lastAccruedWeight The last recorded accrued weight of the yield token.
    function positions(
        address owner,
        address yieldToken
    )
        external
        view
        returns (
            uint256 shares,
            uint256 harvestedYield,
            uint256 lastAccruedWeight
        );

    /// @notice Gets the amount of debt tokens `spender` is allowed to borrow on behalf of `owner`.
    ///
    /// @param owner   The owner of the account.
    /// @param spender The address which is allowed to borrow on behalf of `owner`.
    ///
    /// @return allowance The amount of debt tokens that `spender` can borrow on behalf of `owner`.
    function borrowAllowance(
        address owner,
        address spender
    ) external view returns (uint256 allowance);

    /// @notice Gets the amount of shares of `yieldToken` that `spender` is allowed to withdraw on behalf of `owner`.
    ///
    /// @param owner      The owner of the account.
    /// @param spender    The address which is allowed to withdraw on behalf of `owner`.
    /// @param yieldToken The address of the yield token.
    ///
    /// @return allowance The amount of shares that `spender` can withdraw on behalf of `owner`.
    function withdrawAllowance(
        address owner,
        address spender,
        address yieldToken
    ) external view returns (uint256 allowance);

    /// @notice Get YieldStrategyManager contract handle.
    /// @return returns YieldStrategyManager contract handle.
    function yieldStrategyManager()
        external
        view
        returns (IYieldStrategyManager);

    /// @notice Check interfaceId is supported by SavvyPositionManager.
    /// @param interfaceId The Id of interface to check.
    /// @return SavvyPositionMananger supports this interfaceId or not. true/false.
    function supportInterface(bytes4 interfaceId) external view returns (bool);
}

