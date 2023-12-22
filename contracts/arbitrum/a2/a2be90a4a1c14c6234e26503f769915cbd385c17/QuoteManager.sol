// SPDX-License-Identifier: NONE
pragma solidity >=0.8.9 <=0.8.19;

import "./Initializable.sol";
import "./IFixedRateMarket.sol";
import "./IQollateralManager.sol";
import "./IQuoteManager.sol";
import "./IQAdmin.sol";
import "./CustomErrors.sol";
import "./Interest.sol";
import "./LinkedList.sol";
import "./QTypes.sol";

contract QuoteManager is Initializable, IQuoteManager {
    
  using LinkedList for LinkedList.OrderbookSide;
  
  /// @notice Borrow side enum
  uint8 private constant _SIDE_BORROW = 0;

  /// @notice Lend side enum
  uint8 private constant _SIDE_LEND = 1;
  
  /// @notice Internal representation on null pointer for linked lists
  uint64 private constant _NULL_POINTER = 0;

  /// @notice Token dust size - effectively treat it as zero
  uint private constant _DUST = 100;
  
  /// @notice Reserve storage gap so introduction of new parent class later on can be done via upgrade
  uint256[50] __gap;
  
  /// @notice Contract storing all global Qoda parameters
  IQAdmin private _qAdmin;
  
  /// @notice Contract managing execution of market quotes 
  IFixedRateMarket private _market;
  
  /// @notice Linked list representation of lend side of the orderbook
  LinkedList.OrderbookSide private _lendQuotes;

  /// @notice Linked list representation of borrow side of the orderbook
  LinkedList.OrderbookSide private _borrowQuotes;
  
  /// @notice Storage for live borrow `Quote` id's by account
  mapping(address => uint64[]) private _accountBorrowQuotes;

  /// @notice Storage for live lend `Quote` id's by account
  mapping(address => uint64[]) private _accountLendQuotes;
  
  constructor() {
    _disableInitializers();
  }
  
  /// @notice Constructor for upgradeable contracts
  /// @param qAdminAddr_ Address of the `QAdmin` contract
  /// @param marketAddr_ Address of the `FixedRateMarket` contract
  function initialize(address qAdminAddr_, address marketAddr_) public initializer {
    _qAdmin = IQAdmin(qAdminAddr_);
    _market = IFixedRateMarket(marketAddr_);
  }
  
  modifier onlyMarket() {
    if (!_qAdmin.hasRole(_qAdmin.MARKET_ROLE(), msg.sender)) {
      revert CustomErrors.QUM_OnlyMarket();
    }
    _;
  }
  
  /// @notice Modifier which checks that contract and specified operation is not paused 
  modifier whenNotPaused(uint operationId) {
    if (_qAdmin.isPaused(address(this), operationId)) {
      revert CustomErrors.QUM_OperationPaused(operationId);
    }
    _;
  }
  
  /** USER INTERFACE **/
  
  /// @notice Creates a new  `Quote` and adds it to the `OrderbookSide` linked list by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quoter Account of the Quoter
  /// @param quoteType 0 for PV+APR, 1 for FV+APR
  /// @param APR In decimal form scaled by 1e4 (ex. 1052 = 10.52%)
  /// @param cashflow Can be PV or FV depending on `quoteType`
  function createQuote(uint8 side, address quoter, uint8 quoteType, uint64 APR, uint cashflow) external whenNotPaused(401) {
    _createQuote(side, quoter, quoteType, APR, cashflow);
  }
  
  /// @notice Cancel `Quote` by id. Note this is a O(1) operation
  /// since `OrderbookSide` uses hashmaps under the hood. However, it is
  /// O(n) against the array of `Quote` ids by account so we should ensure
  /// that array should not grow too large in practice.
  /// @param isUserCanceled True if user actively canceled `Quote`, false otherwise
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quoter Address of the `Quoter`
  /// @param id Id of the `Quote`
  function cancelQuote(bool isUserCanceled, uint8 side, address quoter, uint64 id) external whenNotPaused(402) {
    _cancelQuote(isUserCanceled, side, quoter, id);
  }
  
  /// @notice Fill existing `Quote` by side and id
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  /// @param amount Amount to be filled
  function fillQuote(uint8 side, uint64 id, uint amount) external onlyMarket {
    _fillQuote(side, id, amount);
  }
  
  /** VIEW FUNCTIONS **/

  /// @notice Get the address of the `QAdmin`
  /// @return address
  function qAdmin() external view returns(address) {
    return address(_qAdmin);
  }
  
  /// @notice Get the address of the `FixedRateMarket`
  /// @return address
  function fixedRateMarket() external view returns(address){
    return address(_market);
  }
  
  /// @notice Get the minimum quote size for this market
  /// @return uint Minimum quote size, in PV terms, local currency
  function minQuoteSize() external view returns(uint) {
    return _qAdmin.minQuoteSize(address(this));
  }

  /// @notice Get the linked list pointer top of book for `Quote` by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return uint64 id of top of book `Quote` 
  function getQuoteHeadId(uint8 side) external view returns(uint64) {
    return _getQuoteHeadId(side);
  }

  /// @notice Get the top of book for `Quote` by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return QTypes.Quote head `Quote`
  function getQuoteHead(uint8 side) external view returns(QTypes.Quote memory) {
    return _getQuoteHead(side);
  }
  
  /// @notice Get the `Quote` for the given `side` and `id`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of `Quote`
  /// @return QTypes.Quote `Quote` associated with the id
  function getQuote(uint8 side, uint64 id) external view returns(QTypes.Quote memory) {
    return _getQuote(side, id);
  }
  
  /// @notice Get all live `Quote` id's by `account` and `side`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param account Account to query
  /// @return uint[] Unsorted array of borrow `Quote` id's
  function getAccountQuotes(uint8 side, address account) external view returns(uint64[] memory) {
    return _getMutAccountQuotes(side, account);
  }

  /// @notice Get the number of active `Quote`s by `side` in the orderbook
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return uint Number of `Quote`s
  function getNumQuotes(uint8 side) external view returns(uint) {
    if(side == _SIDE_BORROW) {
      return uint(_borrowQuotes.length);
    } else if(side == _SIDE_LEND) {
      return uint(_lendQuotes.length);
    } else {
      revert CustomErrors.QUM_InvalidSide();
    }
  }
  
  /// @notice Checks whether a `Quote` is still valid. Importantly, for lenders,
  /// we need to check if the `Quoter` currently has enough balance to perform
  /// a lend, since the `Quoter` can always remove balance/allowance immediately
  /// after creating the `Quote`. Likewise, for borrowers, we need to check if
  /// the `Quoter` has enough collateral to perform a borrow, since the `Quoter`
  /// can always remove collateral immediately after creating the `Quote`.
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quote `Quote` to check for validity
  /// @return bool True if valid false otherwise
  function isQuoteValid(uint8 side, QTypes.Quote memory quote) external view returns(bool) {
    return _isQuoteValid(side, quote);
  }
  
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
                 ) public view returns(uint) {
    
    if(quoteType == 0) {

      // `amount` is already in PV terms, just return self
      return amount;

    } else if(quoteType == 1) {

      // `amount` is in FV terms - needs to be explicitly converted to PV
      return Interest.FVToPV(
                             APR,
                             amount,
                             sTime,
                             eTime,
                             _qAdmin.MANTISSA_BPS()
                             );

      
    } else {
      revert CustomErrors.QUM_InvalidQuoteType();
    }    
  }

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
                 ) public view returns(uint) {
    
    if(quoteType == 0) {

      // `amount` is in PV terms - needs to be explicitly converted to FV
      return Interest.PVToFV(
                             APR,
                             amount,
                             sTime,
                             eTime,
                             _qAdmin.MANTISSA_BPS()
                             );
      
    } else if(quoteType == 1) {

      // `amount` is already in FV terms, just return self
      return amount;
      
    } else {
      revert CustomErrors.QUM_InvalidQuoteType();
    }    
  }
  
  /** INTERNAL FUNCTIONS **/
    
  /// @notice Creates a new  `Quote` and adds it to the `OrderbookSide` linked list by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quoter Account of the Quoter
  /// @param quoteType 0 for PV+APR, 1 for FV+APR
  /// @param APR In decimal form scaled by 1e4 (ex. 1052 = 10.52%)
  /// @param cashflow Can be PV or FV depending on `quoteType`
  function _createQuote(uint8 side, address quoter, uint8 quoteType, uint64 APR, uint cashflow) internal {

    // Pre-flight checks
    _createQuoteChecks(side, quoter, quoteType, APR, cashflow);

    // Get mutable instance of `OrderbookSide`
    LinkedList.OrderbookSide storage quotes = _getMutOrderbookSide(side);

    uint64 id;
    if(quotes.head == _NULL_POINTER) {

      // `OrderbookSide` is currently empty, set the new `Quote` as the top of book      
      id = quotes.addHead(quoter, quoteType, APR, cashflow);
      
    } else {

      // Get the current head `Quote`
      QTypes.Quote memory curr = quotes.get(quotes.head);

      bool inserted = false;
      while (curr.id != _NULL_POINTER) {
        if((side == _SIDE_BORROW && APR > curr.APR) || (side == _SIDE_LEND && APR < curr.APR)) {
          // The new `Quote` has more competitive APR than the current so insert it before
          id = quotes.insertBefore(curr.id, quoter, quoteType, APR, cashflow);
          inserted = true;
          break;
        } else {
          curr = quotes.get(curr.next);
        }
      }

      // If the new `Quote` still has not been inserted, this means it is the
      // bottom of book, so insert it as the tail of the linked list
      if(!inserted) {
        id = quotes.addTail(quoter, quoteType, APR, cashflow);
      }
    }

    // Add the id to the list of account `Quote`s
    uint64[] storage accountQuotes = _getMutAccountQuotes(side, quoter);
    accountQuotes.push(id);

    // Emit the event
    emit CreateQuote(side, quoter, id, quoteType, APR, cashflow);
    
    // Invoke create quote handler
    _market._onCreateQuote(side, id);
  }
  

  /// @notice Cancel `Quote` by id. Note this is a O(1) operation
  /// since `OrderbookSide` uses hashmaps under the hood. However, it is
  /// O(n) against the array of `Quote` ids by account so we should ensure
  /// that array should not grow too large in practice.
  /// @param isUserCanceled True if user actively canceled `Quote`, false otherwise
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quoter Address of the `Quoter`
  /// @param id Id of the `Quote`
  function _cancelQuote(bool isUserCanceled, uint8 side, address quoter, uint64 id) internal {
    // Sender must be either owner of quotes or market
    // Currently market will only cancel quote on behalf of msg.sender,
    // so it is also safe if sender comes from market as well
    if (msg.sender != quoter && msg.sender != address(_market)) {
      revert CustomErrors.QUM_NotQuoteOwner();
    }

    // Get the `Quote` associated with the `side` and `id`
    QTypes.Quote memory quote = _getQuote(side, id);

    // Make sure the caller is authorized to cancel the `Quote`
    if (quoter != quote.quoter) {
      revert CustomErrors.QUM_Unauthorized();
    }

    // Remove `Quote` id from account `Quote`s list
    // Since Solidity arrays are inherently hacky, we use a hacky method
    // for deleting array elements.
    // We find the index of the `accountQuotes` array element to delete,
    // move the last element to the deleted spot, and then remove the
    // last element.
    // Note: This means order will not be preserved in the `accountQuotes` array.
    uint64[] storage accountQuotes = _getMutAccountQuotes(side, quoter);
    uint accountQuotesLength = accountQuotes.length;
    uint idx = type(uint256).max;
    for (uint i = 0; i < accountQuotesLength;) {
      if(id == accountQuotes[i]) {
        idx = i;
        break;
      }
      unchecked { i++; }
    }  
    if (idx >= accountQuotesLength) {
      revert CustomErrors.QUM_QuoteNotFound();
    }
    accountQuotes[idx] = accountQuotes[accountQuotesLength - 1];
    accountQuotes.pop();    

    // Emit the event
    emit RemoveQuote(quote.quoter, isUserCanceled, side, id, quote.quoteType, quote.APR, quote.cashflow, quote.filled);
    
    // Cancel the `Quote`
    if(side == _SIDE_BORROW){
      _borrowQuotes.remove(id);
    }else if(side == _SIDE_LEND) {
      _lendQuotes.remove(id);
    }
    
    // Invoke cancel quote handler
    _market._onCancelQuote(side, id);
  }
  
  /// @notice Fill existing `Quote` by side and id
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  /// @param amount Amount to be filled
  function _fillQuote(uint8 side, uint64 id, uint amount) internal {
    // Get the `Quote` associated with the `side` and `id`
    QTypes.Quote storage quote = _getMutQuote(side, id);
    if (quote.filled + amount > quote.cashflow) {
      revert CustomErrors.QUM_InvalidFillAmount();
    }
    quote.filled += amount;

    // Invoke fill quote handler
    _market._onFillQuote(side, id);
  }
  
  /** INTERNAL VIEW FUNCTIONS **/
  
  /// @notice Get the linked list pointer top of book for `Quote` by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return uint64 id of top of book `Quote` 
  function _getQuoteHeadId(uint8 side) internal view returns(uint64) {
    if(side == _SIDE_BORROW) {
      return _borrowQuotes.head;
    }else if(side == _SIDE_LEND) {
      return _lendQuotes.head;
    }else {
      revert CustomErrors.QUM_InvalidSide();
    }
  }
  
  /// @notice Get the top of book for `Quote` by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return QTypes.Quote head `Quote`
  function _getQuoteHead(uint8 side) internal view returns(QTypes.Quote memory) {
    return _getQuote(side, _getQuoteHeadId(side));
  }
  
  /// @notice Get the `Quote` for the given `side` and `id`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of `Quote`
  /// @return QTypes.Quote `Quote` associated with the id
  function _getQuote(uint8 side, uint64 id) internal view returns(QTypes.Quote memory) {
    if(side == _SIDE_BORROW) {
      return _borrowQuotes.quotes[id];
    } else if(side == _SIDE_LEND) {
      return _lendQuotes.quotes[id];
    } else {
      revert CustomErrors.QUM_InvalidSide();
    }
  }

  /// @notice Get a MUTABLE instance of `Quote` for the given `side` and `id`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of `Quote`
  /// @return QTypes.Quote Mutable instance of `Quote` associated with the id
  function _getMutQuote(uint8 side, uint64 id) internal view returns(QTypes.Quote storage) {
    if(side == _SIDE_BORROW) {
      return _borrowQuotes.quotes[id];
    } else if(side == _SIDE_LEND) {
      return _lendQuotes.quotes[id];
    } else {
      revert CustomErrors.QUM_InvalidSide();
    }
  }
  
  /// @notice Get a MUTABLE instance of all live `Quote` id's by `account` and `side`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param account Account to query
  /// @return uint[] Unsorted array of borrow `Quote` id's
  function _getMutAccountQuotes(uint8 side, address account) internal view returns(uint64[] storage) {
    if(side == _SIDE_BORROW) {
      return _accountBorrowQuotes[account];
    } else if(side == _SIDE_LEND) {
      return _accountLendQuotes[account];
    } else {
      revert CustomErrors.QUM_InvalidSide();
    }
  }

  /// @notice Get a MUTABLE instance of the `OrderbookSide` by `side`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return LinkedList.OrderbookSide Mutable instance of orderbook side
  function _getMutOrderbookSide(uint8 side) internal view returns(LinkedList.OrderbookSide storage) {
    if(side == _SIDE_BORROW) {
      return _borrowQuotes;
    } else if(side == _SIDE_LEND) {
      return _lendQuotes;
    } else {
      revert CustomErrors.QUM_InvalidSide();
    }
  }
  
  /// @notice Some preflight checks before user can successfully create `Quote`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quoter Account of the Quoter
  /// @param quoteType 0 for PV+APR, 1 for FV+APR
  /// @param APR In decimal form scaled by 1e4 (ex. 1052 = 10.52%)
  /// @param cashflow Can be PV or FV depending on `quoteType`
  /// @return bool True If passes all tests false otherwise
  function _createQuoteChecks(
                              uint8 side,
                              address quoter,
                              uint8 quoteType,
                              uint64 APR,
                              uint cashflow
                              ) internal view returns(bool) {
    
    // Sender must be either owner of quotes or market
    // Currently market will only create quote on behalf of msg.sender,
    // so it's also safe if sender comes from market as well 
    if (msg.sender != quoter && msg.sender != address(_market)) {
      revert CustomErrors.QUM_NotQuoteOwner();
    }
    
    // `cashflow` must be positive
    if (cashflow <= 0) {
      revert CustomErrors.QUM_InvalidCashflowSize();
    }

    // Only {0,1} are valid `quoteType`s. 0 for PV+APR, for FV+APR
    if (quoteType > 1) {
      revert CustomErrors.QUM_InvalidQuoteType();
    }

    // Get the PV of the  amount of the `Quote`
    uint amountPV = getPV(quoteType, APR, cashflow, block.timestamp, _market.maturity());

    // Get the FV of the amount of the `Quote`
    uint amountFV = getFV(quoteType, APR, cashflow, block.timestamp, _market.maturity());
    
    // Quote size must be above minimum in PV terms, local currency
    if (amountPV < _qAdmin.minQuoteSize(address(_market))) {
      revert CustomErrors.QUM_QuoteSizeTooSmall();
    }

    if (side == _SIDE_BORROW) {

      // Check if borrowing amount is breaching maximum allow amount borrow
      IQollateralManager qm = IQollateralManager(_qAdmin.qollateralManager());
      uint maxBorrowFV = qm.hypotheticalMaxBorrowFV(quoter, _market);
      if (amountFV > maxBorrowFV) {
        revert CustomErrors.QUM_MaxBorrowExceeded();
      }
      
    } else if(side == _SIDE_LEND) {

      uint protocolFee_ = _market.proratedProtocolFee(amountPV);
      
      // User must have enough balance to cover PV if lending
      if (_market.underlyingToken().balanceOf(quoter) < amountPV + protocolFee_) {
        revert CustomErrors.QUM_InsufficientBalance();
      }
      
      // User must have enough allowance to cover PV if lending
      if (_market.underlyingToken().allowance(quoter, address(_market)) < amountPV + protocolFee_) {
        revert CustomErrors.QUM_InsufficientAllowance();
      }
      
    } else {
      revert CustomErrors.QUM_InvalidSide();
    }

    // `Quote` passes all checks
    return true;
  }
  
  /// @notice Checks whether a `Quote` is still valid. Importantly, for lenders,
  /// we need to check if the `Quoter` currently has enough balance to perform
  /// a lend, since the `Quoter` can always remove balance/allowance immediately
  /// after creating the `Quote`. Likewise, for borrowers, we need to check if
  /// the `Quoter` has enough collateral to perform a borrow, since the `Quoter`
  /// can always remove collateral immediately after creating the `Quote`.
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quote `Quote` to check for validity
  /// @return bool True if valid false otherwise
  function _isQuoteValid(uint8 side, QTypes.Quote memory quote) internal view returns(bool) {

    // `Quote` is fully consumed. Note: We need to use a non-zero dust size here
    // to handle edge cases such as if a dust-sized FV value is rounded down to
    // zero PV. This could cause a `Quote` to be stuck or reverting forever.
    if(quote.cashflow - quote.filled < _DUST) {
      return false;
    }

    // Get the remaining amount of the `Quote`
    uint amountRemaining = quote.cashflow - quote.filled;
    
    // Get the PV of the remaining amount
    uint amountPV = getPV(quote.quoteType, quote.APR, amountRemaining, block.timestamp, _market.maturity());

    // Get the FV of the remaining amount
    uint amountFV = getFV(quote.quoteType, quote.APR, amountRemaining, block.timestamp, _market.maturity());

    // Protocol fees need to be covered by balance for lenders
    uint protocolFee_ = _market.proratedProtocolFee(amountPV);

    // Quoter must have enough balance to cover PV if lending
    if(side == _SIDE_LEND && _market.underlyingToken().balanceOf(quote.quoter) < amountPV + protocolFee_) {
      return false;
    }

    // Quoter must have enough allowance to cover PV if lending
    if(side == _SIDE_LEND && _market.underlyingToken().allowance(quote.quoter, address(_market)) < amountPV + protocolFee_) {
      return false;
    }
    
    if(side == _SIDE_BORROW) {
      // Borrower must have enough collateral to avoid breaching init collateral ratio, 
      // and must not breach credit limit granted
      IQollateralManager qm = IQollateralManager(_qAdmin.qollateralManager());
      uint maxBorrowFV = qm.hypotheticalMaxBorrowFV(quote.quoter, _market);
      if (amountFV > maxBorrowFV) {
        return false;
      }
    }

    // Passes all checks - `Quote` is valid
    return true;        
  }
}

