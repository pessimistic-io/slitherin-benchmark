// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

abstract contract IRequestControllerInternals {

    function _sendWithdraw(
        address user,
        address route,
        uint256 withdrawAmount,
        address pToken,
        uint256 targetChainId
    ) internal virtual;

    function _sendBorrow(
        address user,
        address route,
        address loanMarketAsset,
        uint256 borrowAmount,
        uint256 targetChainId
    ) internal virtual;

    function _sendRepay(
        address payer,
        address borrower,
        address route,
        address loanMarketAsset,
        uint256 repayAmount
    ) internal virtual returns (uint256);

}

