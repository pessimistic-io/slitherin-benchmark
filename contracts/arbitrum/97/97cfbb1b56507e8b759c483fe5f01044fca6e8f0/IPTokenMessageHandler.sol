// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IHelper.sol";

abstract contract IPTokenMessageHandler {

    function _sendDeposit(
        address route,
        address user,
        uint256 gas,
        uint256 depositAmount,
        uint256 externalExchangeRate
    ) internal virtual;

    function completeWithdraw(
        IHelper.FBWithdraw memory params
    ) external payable virtual;

    function seize(
        IHelper.SLiquidateBorrow memory params
    ) external payable virtual;
}

