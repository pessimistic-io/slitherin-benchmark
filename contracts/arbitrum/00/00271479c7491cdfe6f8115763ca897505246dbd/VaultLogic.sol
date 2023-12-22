// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {TransferHelper} from "./TransferHelper.sol";
import {BaseContract} from "./BaseContract.sol";

import {IVaultLogic} from "./IVaultLogic.sol";

/// @title VaultLogic
/// @notice This contract is used to deposit and withdraw funds from the Vault
contract VaultLogic is IVaultLogic, BaseContract {
    using TransferHelper for address;

    // =========================
    // Functions
    // =========================

    /// @inheritdoc IVaultLogic
    function depositNative() external payable {
        emit DepositNative(msg.sender, msg.value);
    }

    /// @inheritdoc IVaultLogic
    function depositERC20(
        address token,
        uint256 amount,
        address depositor
    ) external onlyOwnerOrVaultItself {
        token.safeTransferFrom(depositor, address(this), amount);
        emit DepositERC20(depositor, token, amount);
    }

    /// @inheritdoc IVaultLogic
    function withdrawNative(
        address receiver,
        uint256 amount
    ) external onlyOwnerOrVaultItself {
        receiver.safeTransferNative(amount);

        emit WithdrawNative(receiver, amount);
    }

    /// @inheritdoc IVaultLogic
    function withdrawTotalNative(
        address receiver
    ) external onlyOwnerOrVaultItself {
        uint256 amount = address(this).balance;

        receiver.safeTransferNative(amount);

        emit WithdrawNative(receiver, amount);
    }

    /// @inheritdoc IVaultLogic
    function withdrawERC20(
        address token,
        address receiver,
        uint256 amount
    ) external onlyOwnerOrVaultItself {
        token.safeTransfer(receiver, amount);
        emit WithdrawERC20(receiver, token, amount);
    }

    /// @inheritdoc IVaultLogic
    function withdrawTotalERC20(
        address token,
        address receiver
    ) external onlyOwnerOrVaultItself {
        uint256 amount = token.safeGetBalance(address(this));

        token.safeTransfer(receiver, amount);
        emit WithdrawERC20(receiver, token, amount);
    }
}

