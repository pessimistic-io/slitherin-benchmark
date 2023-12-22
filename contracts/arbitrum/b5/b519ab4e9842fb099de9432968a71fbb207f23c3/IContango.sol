//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libraries_DataTypes.sol";

import "./IContangoView.sol";

struct SwapInfo {
    Currency inputCcy;
    int256 input;
    int256 output;
    uint256 price;
}

struct Trade {
    int256 quantity;
    SwapInfo swap;
    Currency cashflowCcy;
    int256 cashflow;
    uint256 fee;
    Currency feeCcy;
    uint256 forwardPrice;
}

struct TradeParams {
    PositionId positionId;
    int256 quantity;
    uint256 limitPrice; // in quote currency
    Currency cashflowCcy;
    int256 cashflow;
}

struct ExecutionParams {
    Dex dex;
    uint256 swapAmount;
    bytes swapBytes;
    FlashLoanProvider flashLoanProvider;
}

interface IContangoEvents {
    event PositionUpserted(
        PositionId indexed positionId,
        address indexed owner,
        address indexed tradedBy,
        Currency cashflowCcy,
        int256 cashflow,
        int256 quantityDelta,
        uint256 price,
        uint256 fee,
        Currency feeCcy
    );
}

interface IContango is IContangoEvents, IContangoView {
    error ClosingOnly(); // 0x1dacbd6f
    error OnlyFullClosureAllowedAfterExpiry(); // 0x62a73c9a
    error ExcessiveInputQuote(uint256 limit, uint256 actual); // 0x937d5fee
    error ExcessiveRemainingQuote(uint256 limit, uint256 actual); // 0xdf225344
    error InsufficientBaseOnOpen(uint256 expected, int256 actual); // 0x49cb41d9
    error InsufficientBaseCashflow(int256 expected, int256 actual); // 0x0ef42287
    error InvalidFlashLoanProvider(FlashLoanProvider id); // 0x6b8e2c0a
    error InvalidInstrument(Symbol symbol); // 0x2d5bccd2
    error NotFlashLoanProvider(address msgSender, address expected, FlashLoanProvider id); // 0xbcdbc821
    error NotFlashBorrowProvider(address msgSender);
    error NotInitiatedByContango();
    error PriceAboveLimit(uint256 limit, uint256 actual); // 0x6120c45f
    error PriceBelowLimit(uint256 limit, uint256 actual); // 0x756cfc28

    function trade(TradeParams calldata tradeParams, ExecutionParams calldata execParams)
        external
        payable
        returns (PositionId positionId, Trade memory trade);

    function tradeOnBehalfOf(TradeParams calldata tradeParams, ExecutionParams calldata execParams, address onBehalfOf)
        external
        payable
        returns (PositionId positionId, Trade memory trade);
}

