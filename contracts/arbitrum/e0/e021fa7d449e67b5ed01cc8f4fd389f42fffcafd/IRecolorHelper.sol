// SPDX-License-Identifier: LZBL-1.1
// Copyright 2023 LayerZero Labs Ltd.
// You may obtain a copy of the License at
// https://github.com/LayerZero-Labs/license/blob/main/LICENSE-LZBL-1.1

pragma solidity ^0.8.0;

import "./IOFT.sol";

interface IRecolorHelper {
    /// ------ local transfer function -----

    /// @dev send USDV into this account and then ATOMICALLY transfer out with color
    function transferWithColor(address _receiver, uint256 _amount, uint32 _toColor) external;

    /// @dev it requires the caller to approve this contract to spend their USDV
    function approvedTransferWithColor(address _receiver, uint256 _amount, uint32 _toColor) external;

    /// ------ crosschain transfer function transfer function -----

    /// @dev send USDV into this account and then ATOMICALLY send across-chain
    function sendWithColor(
        IOFT.SendParam calldata _param,
        uint32 _toColor,
        bytes calldata _extraOptions,
        MessagingFee calldata _msgFee,
        address payable _refundAddress,
        bytes calldata _composeMsg
    ) external payable returns (MessagingReceipt memory);

    /// @dev it requires the caller to approve this contract to spend their USDV
    function approvedSendWithColor(
        IOFT.SendParam calldata _param,
        uint32 _toColor,
        bytes calldata _extraOptions,
        MessagingFee calldata _msgFee,
        address payable _refundAddress,
        bytes calldata _composeMsg
    ) external payable returns (MessagingReceipt memory);
}

