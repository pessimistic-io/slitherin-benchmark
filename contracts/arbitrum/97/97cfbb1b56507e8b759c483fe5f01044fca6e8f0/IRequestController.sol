// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IHelper.sol";

abstract contract IRequestController {

    /*** User Functions ***/

    function deposit(
        address route,
        address user,
        uint256 amount,
        address pTokenAddress
    ) external payable virtual;

    function withdraw(
        address route,
        uint256 withdrawAmount,
        address pToken,
        uint256 targetChainId
    ) external virtual payable;

    function borrow(
        address route,
        address loanMarketAsset,
        uint256 borrowAmount,
        uint256 targetChainId
    ) external payable virtual;

    function repayBorrow(
        address route,
        address loanMarketAsset,
        uint256 repayAmount
    ) external payable virtual returns (uint256);

    function repayBorrowBehalf(
        address borrower,
        address route,
        address loanMarketAsset,
        uint256 repayAmount
    ) external payable virtual returns (uint256);

    function borrowApproved(
        IHelper.FBBorrow memory params
    ) external payable virtual;

    function unlockLiquidationRefund(
        IHelper.SRefundLiquidator memory params
    ) external payable virtual;

    /*** Admin Functions ***/

    function setMidLayer(address newMiddleLayer) external virtual;

    function deprecateMarket(address loanMarketAsset, bool deprictedStatus) external virtual;

    function freezeLoanMarket(address loanMarketAsset, bool freezeStatus) external virtual;

    function freezePToken(address pToken, bool freezeStatus) external virtual;
}

