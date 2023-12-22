// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IHelper.sol";

abstract contract IMasterMessageHandler {
    function _satelliteLiquidateBorrow(
        address seizeToken,
        uint256 seizeTokenChainId,
        address borrower,
        address liquidator,
        uint256 seizeTokens
    ) internal virtual;

    function _satelliteRefundLiquidator(
        uint256 chainId,
        address liquidator,
        uint256 refundAmount,
        address pToken,
        uint256 seizeAmount
    ) internal virtual;

    function masterLiquidationRequest(
        IHelper.MLiquidateBorrow memory params,
        uint256 chainId
    ) external virtual payable;

    function masterDeposit(
        IHelper.MDeposit memory params,
        uint256 chainId,
        uint256 exchangeRateTimestamp
    ) external virtual payable;

    function masterBorrow(
        IHelper.MBorrow memory params
    ) external virtual payable;

    function masterRepay(
        IHelper.MRepay memory params,
        uint256 chainId
    ) external virtual payable;

    function masterWithdraw(
        IHelper.MWithdraw memory params,
        uint256 exchangeRateTimestamp
    ) external payable virtual;
}

