// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IMasterMessageHandler.sol";
import "./IRequestController.sol";
import "./IPTokenMessageHandler.sol";
import "./ILoanAssetMessageHandler.sol";

abstract contract Selector {
    bytes4 constant MASTER_REPAY = IMasterMessageHandler.masterRepay.selector;
    bytes4 constant MASTER_BORROW = IMasterMessageHandler.masterBorrow.selector;
    bytes4 constant MASTER_DEPOSIT = IMasterMessageHandler.masterDeposit.selector;
    bytes4 constant MASTER_WITHDRAW = IMasterMessageHandler.masterWithdraw.selector;
    bytes4 constant MASTER_LIQUIDATE_BORROW = IMasterMessageHandler.masterLiquidationRequest.selector;

    bytes4 constant FB_BORROW = IRequestController.borrowApproved.selector;
    bytes4 constant SATELLITE_REFUND_LIQUIDATOR = IRequestController.unlockLiquidationRefund.selector;

    bytes4 constant FB_WITHDRAW = IPTokenMessageHandler.completeWithdraw.selector;
    bytes4 constant SATELLITE_LIQUIDATE_BORROW = IPTokenMessageHandler.seize.selector;

    bytes4 constant LOAN_ASSET_BRIDGE = ILoanAssetMessageHandler.mintFromChain.selector;
}
