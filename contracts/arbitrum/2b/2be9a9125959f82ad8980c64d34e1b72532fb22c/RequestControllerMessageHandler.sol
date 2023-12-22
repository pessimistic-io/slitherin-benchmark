// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IHelper.sol";
import "./IRequestController.sol";
import "./IRequestControllerInternals.sol";
import "./RequestControllerModifiers.sol";
import "./ILendable.sol";
import "./RequestControllerEvents.sol";
import "./SafeTransfers.sol";

abstract contract RequestControllerMessageHandler is
    IRequestController,
    IRequestControllerInternals,
    RequestControllerModifiers,
    RequestControllerEvents,
    SafeTransfers
{

    // slither-disable-next-line assembly
    function _sendWithdraw(
        address user,
        address route,
        uint256 withdrawAmount,
        address pToken,
        uint256 targetChainId
    ) internal virtual override {
        bytes memory payload = abi.encode(
            IHelper.MWithdraw({
                metadata: uint256(0),
                selector: MASTER_WITHDRAW,
                pToken: pToken,
                user: user,
                withdrawAmount: withdrawAmount,
                targetChainId: targetChainId
            })
        );

        middleLayer.msend{ value: msg.value }(
            masterCID,
            payload,
            payable(msg.sender),
            route,
            true
        );

        emit WithdrawSent(
            user,
            pToken,
            withdrawAmount
        );
    }

    // slither-disable-next-line assembly
    function _sendBorrow(
        address user,
        address route,
        address loanAsset,
        uint256 borrowAmount,
        uint256 targetChainId
    ) internal virtual override {
        bytes memory payload = abi.encode(
            IHelper.MBorrow({
                metadata: uint256(0),
                selector: MASTER_BORROW,
                user: user,
                borrowAmount: borrowAmount,
                loanAsset: loanAsset,
                targetChainId: targetChainId
            })
        );

        middleLayer.msend{value: msg.value}(
            masterCID,
            payload, // bytes payload
            payable(msg.sender), // refund address
            route,
            true
        );

        emit BorrowSent(
            user,
            address(this),
            loanAsset,
            borrowAmount
        );
    }

    function borrowApproved(
        IHelper.FBBorrow memory params
    ) external payable override virtual onlyMid() {
        if (isLoanMarketFrozen[params.loanAsset]) revert MarketIsFrozen(params.loanAsset);

        ILendable(params.loanAsset).receiveBorrow(params.user, params.borrowAmount);

        emit BorrowComplete(
            params.user,
            address(this),
            params.loanAsset,
            params.borrowAmount
        );
    }

    // slither-disable-next-line assembly
    function _sendRepay(
        address payer,
        address borrower,
        address route,
        address loanAsset,
        uint256 repayAmount
    ) internal virtual override returns (uint256) {

        uint256 _value;
        uint256 _gas = msg.value;
        {
            (bool success, bytes memory ret) = loanAsset.staticcall(
                abi.encodeWithSignature(
                    "underlying()"
                )
            );
            if (success) {
                (address underlying) = abi.decode(ret, (address));
                if (underlying == address(0)) {
                    _value = repayAmount;
                    _gas -= _value;
                }
            }
        }
        ILendable(loanAsset).processRepay{value: _value}(payer, repayAmount);

        bytes memory payload = abi.encode(
            IHelper.MRepay({
                metadata: uint256(0),
                selector: MASTER_REPAY,
                borrower: borrower,
                amountRepaid: repayAmount,
                loanAsset: loanAsset
            })
        );

        middleLayer.msend{ value: _gas }(
            masterCID,
            payload,
            payable(msg.sender),
            route,
            true
        );

        emit RepaySent(
            payer,
            borrower,
            address(this),
            loanAsset,
            repayAmount
        );

        return repayAmount;
    }

     function _sendLiquidation(
        address borrower,
        address route,
        address seizeToken,
        uint256 seizeTokenChainId,
        address loanAsset,
        uint256 repayAmount,
        uint256 gas
    ) internal virtual /* override */ {
        // prepare the payload
        bytes memory payload = abi.encode(
            IHelper.MLiquidateBorrow({
                metadata: uint256(0),
                selector: MASTER_LIQUIDATE_BORROW,
                liquidator: msg.sender,
                borrower: borrower,
                seizeToken: seizeToken,
                seizeTokenChainId: seizeTokenChainId,
                loanAsset: loanAsset,
                repayAmount: repayAmount
            })
        );

        // send the message
        middleLayer.msend{value: gas}(
            masterCID,
            payload, // bytes payload
            payable(msg.sender), // refund address
            route,
            true
        );

        emit LiquidationSent(
            msg.sender,
            borrower,
            seizeToken,
            seizeTokenChainId,
            loanAsset,
            repayAmount,
            address(this)
        );
    }

     function unlockLiquidationRefund(
        IHelper.SRefundLiquidator memory params
    ) external payable override onlyMid() {
        ILendable(params.loanAsset).receiveBorrow(params.liquidator, params.refundAmount);

        emit UnlockedLiquidationRefund(
            params.liquidator,
            params.refundAmount,
            params.loanAsset,
            address(this)
        );
    }
}

