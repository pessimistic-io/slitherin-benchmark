//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

enum Currency {
    None,
    Base,
    Quote
}

function isBase(Currency currency) pure returns (bool) {
    return currency == Currency.Base;
}

function isQuote(Currency currency) pure returns (bool) {
    return currency == Currency.Quote;
}

function isNone(Currency currency) pure returns (bool) {
    return currency == Currency.None;
}

using {isBase, isQuote, isNone} for Currency global;

