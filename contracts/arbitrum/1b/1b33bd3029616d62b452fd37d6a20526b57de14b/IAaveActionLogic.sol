// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAaveActionLogic - AaveActionLogic interface
/// @notice A contract containing the logic for working with the aave protocol
interface IAaveActionLogic {
    // =========================
    // Main functions
    // =========================

    /// @notice Initiates a borrow operation on Aave.
    /// @param borrowToken The address of the token to borrow.
    /// @param amount The amount of the token to borrow.
    function borrowAaveAction(address borrowToken, uint256 amount) external;

    /// @notice Initiates a supply operation on Aave.
    /// @param supplyToken The address of the token to supply.
    /// @param amount The amount of the token to supply.
    function supplyAaveAction(address supplyToken, uint256 amount) external;

    /// @notice Repays a borrow operation on Aave.
    /// @param borrowToken The address of the token to repay.
    /// @param amount The amount of the token to repay.
    function repayAaveAction(address borrowToken, uint256 amount) external;

    /// @notice Initiates a withdraw operation from Aave.
    /// @param supplyToken The address of the token to withdraw.
    /// @param amount The amount of the token to withdraw.
    function withdrawAaveAction(address supplyToken, uint256 amount) external;

    /// @notice Handles emergency repayments on Aave.
    /// @dev Using flashloan totalDebt amount is taken and repaying to the protocol.
    /// Then the whole supply is withdraw, converted to borrowToken and returned loan.
    /// @param supplyToken The address of the token used for repayment.
    /// @param borrowToken The address of the borrowed token.
    /// @param poolFee The pool fee associated with the operation.
    function emergencyRepayAave(
        address supplyToken,
        address borrowToken,
        uint24 poolFee
    ) external;

    /// @notice Executes a callback operation after receiving assets on Aave flash loan.
    /// @param asset The address of the received asset.
    /// @param amount The amount of the received asset.
    /// @param premium The premium amount to be paid to the Flash Loan provider.
    /// @param initiator The address that initiated the operation.
    /// @param params The additional operation data in bytes.
    /// @return Returns a boolean value indicating whether the operation was successful.
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

