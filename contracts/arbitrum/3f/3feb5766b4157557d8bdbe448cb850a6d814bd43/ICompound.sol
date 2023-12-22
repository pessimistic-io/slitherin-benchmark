// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ICToken.sol";
import "./Permit2.sol";

/// @title Compound V2 proxy
/// @author Pino Development Team
/// @notice Calls Compound V2/V3 functions
/// @dev This contract uses Permit2
interface ICompound {
    /// @notice Deposits ERC20 to the Compound protocol and transfers cTokens to the recipient
    /// @param _amount Amount to deposit
    /// @param _cToken Address of the cToken to receive
    /// @param _recipient The destination address that will receive cTokens
    function depositV2(uint256 _amount, ICToken _cToken, address _recipient) external payable;

    /// @notice Deposits ETH to the Compound protocol and transfers CEther to the recipient
    /// @param _recipient The destination address that will receive cTokens
    /// @param _proxyFee Fee of the proxy contract
    /// @dev _proxyFee uses uint96 for storage efficiency
    function depositETHV2(address _recipient, uint96 _proxyFee) external payable;

    /// @notice Deposits WETH, converts it to ETH and mints CEther
    /// @param _permit permit structure to receive WETH
    /// @param _signature Signature used by permit2
    /// @param _recipient The destination address that will receive CEther
    function depositWETHV2(
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature,
        address _recipient
    ) external payable;

    /// @notice Deposits cTokens back to the Compound protocol and receives underlying ERC20 tokens and transfers it to the recipient
    /// @param _amount Amount to withdraw
    /// @param _cToken Address of the cToken
    /// @param _recipient The destination that will receive the underlying token
    function withdrawV2(uint256 _amount, ICToken _cToken, address _recipient) external payable;

    /// @notice Deposits CEther back the the Compound protocol and receives ETH and transfers it to the recipient
    /// @param _amount Amount to withdraw
    /// @param _recipient The destination address that will receive ETH
    function withdrawETHV2(uint256 _amount, address _recipient) external payable;

    /// @notice Deposits CEther back the the Compound protocol and receives ETH and transfers WETH to the recipient
    /// @param _amount Amount to withdraw
    /// @param _recipient The destination address that will receive WETH
    function withdrawWETHV2(uint256 _amount, address _recipient) external payable;

    /// @notice Repays a borrowed token on behalf of the recipient
    /// @param _cToken Address of the cToken
    /// @param _amount Amount to repay
    /// @param _recipient The address of the recipient
    function repayV2(ICToken _cToken, uint256 _amount, address _recipient) external payable;

    /// @notice Repays ETH on behalf of the recipient
    /// @param _recipient The address of the recipient
    /// @param _proxyFee Fee of the proxy contract
    function repayETHV2(address _recipient, uint96 _proxyFee) external payable;

    /// @notice Repays ETH on behalf of the recipient but receives WETH from the caller
    /// @param _permit The permit structure for PERMIT2 to receive WETH
    /// @param _signature The signature used by PERMIT2 contract
    /// @param _recipient The address of the recipient
    function repayWETHV2(
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature,
        address _recipient
    ) external payable;

    /// @notice Deposits ERC20 tokens to the Compound protocol on behalf of the recipient
    /// @param _token The underlying ERC20 token
    /// @param _amount Amount to deposit
    /// @param _recipient The address of the recipient
    function depositV3(address _token, uint256 _amount, address _recipient) external payable;

    /// @notice Withdraws an ERC20 token and transfers it to the recipient
    /// @param _token The underlying ERC20 token to withdraw
    /// @param _amount Amount to withdraw
    /// @param _recipient The address of the recipient
    function withdrawV3(address _token, uint256 _amount, address _recipient) external payable;
}

