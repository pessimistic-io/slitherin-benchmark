// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library Errors {
    error IncorrectFee();
    error NotOpenOrder();
    error NoOpenPositon();
    error InvalidAccount();
    error TransferFailed();
    error InvalidOperator();
    error InvalidExpiration();
    error OrderAlreadyExists();
    error CannotExecuteOrder();
    error OrderAlreadyExecuted();
    error InvalidQuoteAssetAmount();
    error InvalidManagerOrOperator();
}
