// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./PTokenInternals.sol";
import "./PTokenEvents.sol";
import "./PTokenMessageHandler.sol";
import "./PTokenAdmin.sol";

abstract contract PTokenBase is
    IPTokenInternals,
    PTokenInternals,
    PTokenEvents,
    PTokenMessageHandler,
    PTokenAdmin
{
    function initializeBase(
        address _underlying,
        address _middleLayer,
        uint256 _masterCID
    ) internal {
        setContractIdentifier(PTOKEN_IDENTIFIER);

        if (address(_middleLayer) == address(0)) revert AddressExpected();

        if (_masterCID == 0) revert ParamOutOfBounds();

        underlying = _underlying;
        middleLayer = IMiddleLayer(_middleLayer);
        masterCID = _masterCID;
        if (_underlying != address(0)) decimals = PTokenStorage(_underlying).decimals();
        else decimals = 18;

        admin = payable(msg.sender);
    }

    /**
    * @notice Deposits underlying asset into the protocol
    * @param amount The amount of underlying to deposit
    * @param route Route through which to send deposit
    */
    function deposit(
        address route,
        uint256 amount
    ) external virtual override payable sanityDeposit(amount, msg.sender) {
        uint256 externalExchangeRate = _getExternalExchangeRate();
        uint256 actualTransferAmount = _doTransferIn(underlying, msg.sender, amount);

        _sendDeposit(
            route,
            msg.sender,
            underlying == address(0)
                ? msg.value - actualTransferAmount
                : msg.value,
            actualTransferAmount,
            externalExchangeRate
        );
    }

    /**
    * @notice Deposits underlying asset into the protocol
    * @param route Route through which to send deposit
    * @param user The address of the user that is depositing funds
    * @param amount The amount of underlying to deposit
    */
    function depositBehalf(
        address route,
        address user,
        uint256 amount
    ) external virtual override payable onlyRequestController() sanityDeposit(amount, user) {
        uint256 externalExchangeRate = _getExternalExchangeRate();
        uint256 actualTransferAmount = _doTransferIn(underlying, user, amount);

        _sendDeposit(
            route,
            user,
            underlying == address(0)
                ? msg.value - actualTransferAmount
                : msg.value,
            actualTransferAmount,
            externalExchangeRate
        );
    }

    function receiveBorrow(
        address borrower,
        uint256 borrowAmount
    ) external /* override */ onlyRequestController() {
        if (borrowAmount == 0) revert AmountIsZero();

        _doTransferOut(borrower, underlying, borrowAmount);
    }

    function processRepay(
        address repayer,
        uint256 repayAmount
    ) external payable /* override */ onlyRequestController() {
        if (repayAmount == 0) revert AmountIsZero();

        _doTransferIn(underlying, repayer, repayAmount);
    }
}

