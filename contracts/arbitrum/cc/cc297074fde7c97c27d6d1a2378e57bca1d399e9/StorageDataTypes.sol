//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./libraries_DataTypes.sol";

struct InstrumentStorage {
    uint32 maturity;
    uint24 _deprecated;
    ERC20 base;
    bool closingOnly;
    ERC20 quote;
}

struct YieldInstrumentStorage {
    bytes6 baseId;
    bytes6 quoteId;
    IFYToken quoteFyToken;
    IFYToken baseFyToken;
    IPool basePool;
    IPool quotePool;
    uint96 minQuoteDebt;
}

struct NotionalInstrumentStorage {
    uint16 baseId;
    uint16 quoteId;
    uint64 basePrecision;
    uint64 quotePrecision;
    bool isQuoteWeth;
}

