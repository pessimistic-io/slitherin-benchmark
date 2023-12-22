//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./QTypes.sol";

interface IQuoteManager {
  
  /// @notice Emitted when an account creates a new `Quote`
  event CreateQuote(
                    uint8 indexed side,
                    address indexed quoter,
                    uint64 id,
                    uint8 quoteType,
                    uint64 APR,
                    uint cashflow
                    );
  
  /// @notice Emitted when a `Quote` is filled and/or cancelled
  event RemoveQuote(
                    address indexed quoter,
                    bool isUserCanceled,
                    uint8 side,
                    uint64 id,
                    uint8 quoteType,
                    uint64 APR,
                    uint cashflow,
                    uint filled
                    );
  
  /** USER INTERFACE **/
    
  /// @notice Creates a new  `Quote` and adds it to the `OrderbookSide` linked list by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quoter Account of the Quoter
  /// @param quoteType 0 for PV+APR, 1 for FV+APR
  /// @param APR In decimal form scaled by 1e4 (ex. 1052 = 10.52%)
  /// @param cashflow Can be PV or FV depending on `quoteType`
  function createQuote(uint8 side, address quoter, uint8 quoteType, uint64 APR, uint cashflow) external;
    
  /// @notice Cancel `Quote` by id. Note this is a O(1) operation
  /// since `OrderbookSide` uses hashmaps under the hood. However, it is
  /// O(n) against the array of `Quote` ids by account so we should ensure
  /// that array should not grow too large in practice.
  /// @param isUserCanceled True if user actively canceled `Quote`, false otherwise
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quoter Address of the `Quoter`
  /// @param id Id of the `Quote`
  function cancelQuote(bool isUserCanceled, uint8 side, address quoter, uint64 id) external;
    
  /// @notice Fill existing `Quote` by side and id
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  /// @param amount Amount to be filled
  function fillQuote(uint8 side, uint64 id, uint amount) external;
    
  /** VIEW FUNCTIONS **/
  
  /// @notice Get the address of the `QAdmin`
  /// @return address
  function qAdmin() external view returns(address);
  
  /// @notice Get the address of the `FixedRateMarket`
  /// @return address
  function fixedRateMarket() external view returns(address);
    
  /// @notice Get the minimum quote size for this market
  /// @return uint Minimum quote size, in PV terms, local currency
  function minQuoteSize() external view returns(uint);
    
  /// @notice Get the linked list pointer top of book for `Quote` by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return uint64 id of top of book `Quote` 
  function getQuoteHeadId(uint8 side) external view returns(uint64);

  /// @notice Get the top of book for `Quote` by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return QTypes.Quote head `Quote`
  function getQuoteHead(uint8 side) external view returns(QTypes.Quote memory);
  
  /// @notice Get the `Quote` for the given `side` and `id`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of `Quote`
  /// @return QTypes.Quote `Quote` associated with the id
  function getQuote(uint8 side, uint64 id) external view returns(QTypes.Quote memory);

  /// @notice Get all live `Quote` id's by `account` and `side`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param account Account to query
  /// @return uint[] Unsorted array of borrow `Quote` id's
  function getAccountQuotes(uint8 side, address account) external view returns(uint64[] memory);

  /// @notice Get the number of active `Quote`s by `side` in the orderbook
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return uint Number of `Quote`s
  function getNumQuotes(uint8 side) external view returns(uint);
  
  /// @notice Checks whether a `Quote` is still valid. Importantly, for lenders,
  /// we need to check if the `Quoter` currently has enough balance to perform
  /// a lend, since the `Quoter` can always remove balance/allowance immediately
  /// after creating the `Quote`. Likewise, for borrowers, we need to check if
  /// the `Quoter` has enough collateral to perform a borrow, since the `Quoter`
  /// can always remove collateral immediately after creating the `Quote`.
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quote `Quote` to check for validity
  /// @return bool True if valid false otherwise
  function isQuoteValid(uint8 side, QTypes.Quote memory quote) external view returns(bool);
  
  /// @notice Get the PV of a cashflow amount based on the `quoteType`
  /// @param quoteType 0 for PV, 1 for FV
  /// @param APR In decimal form scaled by 1e4 (ex. 10.52% = 1052)
  /// @param sTime PV start time
  /// @param eTime FV end time
  /// @param amount Value to be PV'ed
  /// @return uint PV of the `amount`
  function getPV(
                 uint8 quoteType,
                 uint64 APR,
                 uint amount,
                 uint sTime,
                 uint eTime
                 ) external view returns(uint);

  /// @notice Get the FV of a cashflow amount based on the `quoteType`
  /// @param quoteType 0 for PV, 1 for FV
  /// @param APR In decimal form scaled by 1e4 (ex. 10.52% = 1052)
  /// @param sTime PV start time
  /// @param eTime FV end time
  /// @param amount Value to be FV'ed
  /// @return uint FV of the `amount`
  function getFV(
                 uint8 quoteType,
                 uint64 APR,
                 uint amount,
                 uint sTime,
                 uint eTime
                 ) external view returns(uint);
}

