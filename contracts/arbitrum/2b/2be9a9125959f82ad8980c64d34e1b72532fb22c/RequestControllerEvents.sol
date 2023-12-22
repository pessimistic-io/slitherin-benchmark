// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

abstract contract RequestControllerEvents {

    /*** User Events ***/

    event WithdrawSent(
        address indexed user,
        address indexed pToken,
        uint256 withdrawAmount
    );

    event BorrowSent(
        address user,
        address requestController,
        address loanMarketAsset,
        uint256 amount
    );

    /* 0x9a779823 */
    event RepaySent(
        address payer,
        address borrower,
        address requestController,
        address loanMarketAsset,
        uint256 repayAmount
    );

    /* 0x04890681 */
    event BorrowComplete(
        address indexed borrower,
        address requestController,
        address loanMarketAsset,
        uint256 borrowAmount
    );

    event LiquidationSent(
        address indexed liquidator,
        address indexed borrower,
        address seizeToken,
        uint256 seizeTokenChainId,
        address loanAsset,
        uint256 repayAmount,
        address requestController
    );

    event UnlockedLiquidationRefund(
        address liquidator,
        uint256 refundAmount,
        address pToken,
        address requestController
    );

    /*** Admin Events ***/

    event SetMiddleLayer(
        address oldMiddleLayer,
        address newMiddleLayer
    );

    event MarketDeprecationChanged(
        address loanMarketAsset,
        bool previousStatus,
        bool newStatus
    );

    event LoanMarketFrozen(
        address loanMarketAsset,
        bool previousStatus,
        bool newStatus
    );

    event PTokenFrozen(
        address pToken,
        bool previousStatus,
        bool newStatus
    );
}

