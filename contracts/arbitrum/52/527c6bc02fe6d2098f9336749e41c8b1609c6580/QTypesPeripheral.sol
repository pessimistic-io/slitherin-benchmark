//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9 <=0.8.19;

library QTypesPeripheral {
  
  /// @notice Contains all the fields (market and side included) of a created Quote
  /// @param market Address of the market
  /// @param id ID of the quote
  /// @param side 0 for borrow quote, 1 for lend quote
  /// @param quoter Account of the Quoter
  /// @param quoteType 0 for PV+APR, 1 for FV+APR
  /// @param APR In decimal form scaled by 1e4 (ex. 10.52% = 1052)
  /// @param cashflow Can be PV or FV depending on `quoteType`
  /// @param filled Amount quote has got filled partially 
  struct AccountQuote {
    address market;
    uint64 id;
    uint8 side;
    address quoter;
    uint8 quoteType;
    uint64 APR;
    uint cashflow;
    uint filled;
  }
}

