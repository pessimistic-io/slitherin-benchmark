// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./PTokenStorage.sol";
import "./PTokenInternals.sol";
import "./PTokenModifiers.sol";
import "./PTokenEvents.sol";
import "./IHelper.sol";
import "./IPTokenMessageHandler.sol";
import "./SafeTransfers.sol";

abstract contract PTokenMessageHandler is
    IPTokenInternals,
    IPTokenMessageHandler,
    PTokenModifiers,
    PTokenEvents,
    SafeTransfers
{

    // slither-disable-next-line assembly
    function _sendDeposit(
        address route,
        address user,
        uint256 gas,
        uint256 depositAmount,
        uint256 externalExchangeRate
    ) internal virtual override {

        bytes memory payload = abi.encode(
            IHelper.MDeposit({
                metadata: uint256(0),
                selector: MASTER_DEPOSIT,
                user: user,
                pToken: address(this),
                externalExchangeRate: externalExchangeRate,
                depositAmount: depositAmount
            })
        );

        middleLayer.msend{ value: gas }(
            masterCID,
            payload,
            payable(user),
            route,
            true
        );

        emit DepositSent(user, address(this), depositAmount);
    }

    /**
     * @notice Transfers tokens to the withdrawer.
     */
    function completeWithdraw(
        IHelper.FBWithdraw memory params
    ) external payable virtual override onlyMid() {
        if (isFrozen) revert MarketIsFrozen(address(this));

        emit WithdrawApproved(
            params.user,
            address(this),
            params.withdrawAmount,
            true
        );

        _doTransferOut(params.user, underlying, params.withdrawAmount);
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another PToken.
     *  Its absolutely critical to use msg.sender as the seizer pToken and not a parameter.
     */
    function seize(
        IHelper.SLiquidateBorrow memory params
    ) external payable virtual override onlyMid() {
        if (isFrozen) revert MarketIsFrozen(address(this));

        _doTransferOut(params.liquidator, underlying, params.seizeTokens);
    }
}

