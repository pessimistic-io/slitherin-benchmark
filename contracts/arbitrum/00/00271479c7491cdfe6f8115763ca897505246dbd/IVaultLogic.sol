// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IVaultLogic - VaultLogic interface
/// @notice This contract is used to deposit and withdraw funds from the Vault
interface IVaultLogic {
    // =========================
    // Events
    // =========================

    /// @notice Emits when Native currency is deposited to the contract.
    /// @param depositor Address of the user depositing Native currency.
    /// @param amount Amount of Native currency deposited.
    event DepositNative(address indexed depositor, uint256 amount);

    /// @notice Emits when an ERC20 token is deposited to the contract.
    /// @param depositor Address of the user depositing the ERC20 token.
    /// @param token Address of the ERC20 token being deposited.
    /// @param amount Amount of the ERC20 token deposited.
    event DepositERC20(
        address indexed depositor,
        address indexed token,
        uint256 amount
    );

    /// @notice Emits when Native currency is withdrawn from the contract.
    /// @param receiver Address receiving the Native currency.
    /// @param amount Amount of Native currency withdrawn.
    event WithdrawNative(address indexed receiver, uint256 amount);

    /// @notice Emits when an ERC20 token is withdrawn from the contract.
    /// @param receiver Address receiving the ERC20 token.
    /// @param token Address of the ERC20 token being withdrawn.
    /// @param amount Amount of the ERC20 token withdrawn.
    event WithdrawERC20(
        address indexed receiver,
        address indexed token,
        uint256 amount
    );

    // =========================
    // Functions
    // =========================

    /// @notice Deposits Native currency into the contract.
    /// @dev Amount of deposited value is equivalent to the `msg.value` sent.
    function depositNative() external payable;

    /// @notice Deposits a specified `amount` of ERC20 `tokens` from a `depositor's`
    /// address to the contract.
    /// @param token The address of the ERC20 token to deposit.
    /// @param amount The amount of the token to deposit.
    /// @param depositor The address of the depositor.
    function depositERC20(
        address token,
        uint256 amount,
        address depositor
    ) external;

    /// @notice Withdraws a specified `amount` of Native currency from the contract
    /// to a `receiver's` address.
    /// @param receiver The address to receive the Native currency.
    /// @param amount The amount of Native currency to withdraw.
    function withdrawNative(address receiver, uint256 amount) external;

    /// @notice Withdraws the total balance of Native currency from the contract
    /// to a `receiver's` address.
    /// @param receiver The address to receive the Native currency.
    function withdrawTotalNative(address receiver) external;

    /// @notice Withdraws a specified `amount` of ERC20 `tokens` from the contract
    /// to a `receiver's` address.
    /// @param token The address of the ERC20 token to withdraw.
    /// @param receiver The address to receive the tokens.
    /// @param amount The amount of the token to withdraw.
    function withdrawERC20(
        address token,
        address receiver,
        uint256 amount
    ) external;

    /// @notice Withdraws the total balance of ERC20 `tokens` from the contract
    /// to a `receiver's` address.
    /// @param token The address of the ERC20 token to withdraw.
    /// @param receiver The address to receive the tokens.
    function withdrawTotalERC20(address token, address receiver) external;
}

