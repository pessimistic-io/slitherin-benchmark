// SPDX-License-Identifier: NONE
pragma solidity >=0.8.9 <=0.8.19;

import "./Initializable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./IFeeEmissionsQontroller.sol";
import "./IFixedRateMarket.sol";
import "./ILiquidityEmissionsQontroller.sol";
import "./IQollateralManager.sol";
import "./IQPriceOracle.sol";
import "./ITradingEmissionsQontroller.sol";
import "./IQAdmin.sol";
import "./IQuoteManager.sol";
import "./IQToken.sol";
import "./CustomErrors.sol";
import "./Interest.sol";
import "./LinkedList.sol";
import "./QTypes.sol";
import "./Utils.sol";

contract FixedRateMarket is Initializable, IFixedRateMarket {

  using SafeERC20 for IERC20;
  using LinkedList for LinkedList.OrderbookSide;

  /// @notice Reserve storage gap so introduction of new parent class later on can be done via upgrade
  uint256[150] __gap;
  
  /// @notice Borrow side enum
  uint8 private constant _SIDE_BORROW = 0;

  /// @notice Lend side enum
  uint8 private constant _SIDE_LEND = 1;

  /// @notice Internal representation on null pointer for linked lists
  uint64 private constant _NULL_POINTER = 0;

  /// @notice Token dust size - effectively treat it as zero
  uint private constant _DUST = 100;
  
  /// @notice Contract storing all global Qoda parameters
  IQAdmin private _qAdmin;

  /// @notice Address of the ERC20 token which the loan will be denominated
  IERC20 private _underlying;
  
  /// @notice UNIX timestamp (in seconds) when the market matures
  uint private _maturity;

  /// @notice Storage for all borrows by a user
  /// account => principalPlusInterest
  mapping(address => uint) private _accountBorrows;

  /// @notice (Deprecated) Storage for qTokens redeemed so far by a user
  /// account => qTokensRedeemed
  mapping(address => uint) private _tokensRedeemed;

  /// @notice (Deprecated) Tokens redeemed across all users so far
  uint private _tokensRedeemedTotal;

  /// @notice Total protocol fee accrued in this market so far, in local currency
  uint private _totalAccruedFees;

  /// @notice For calculation of prorated protocol fee
  uint private constant ONE_YEAR_IN_SECONDS = 365 * 24 * 60 * 60;
  
  /// @notice Contract managing quotes
  IQuoteManager private _quoteManager;
  
  uint256 private constant _NOT_ENTERED = 1;
  uint256 private constant _ENTERED = 2;
  
  /// @notice Same as _status in `@openzeppelin/contracts/security/ReentrancyGuard.sol`
  /// Reconstruct here instead of inheritance is to avoid storage slot sequence problem 
  /// during contract upgrade, as well as saving contract size with use of custom error
  uint256 private _status;
  
  /// @notice Name of this contract
  string private _name;
  
  /// @notice Symbol representing this contract
  string private _symbol;
  
  /// @notice Contract managing qTokens
  IQToken private _qToken;
  
  constructor() {
    _disableInitializers();
  }

  /// @notice Constructor for upgradeable contracts
  /// @param qAdminAddr_ Address of the `QAdmin` contract
  /// @param underlyingAddr_ Address of the underlying loan token denomination
  /// @param maturity_ UNIX timestamp (in seconds) when the market matures
  /// @param name_ Name of the market's ERC20 token
  /// @param symbol_ Symbol of the market's ERC20 token
  function initialize(
                      address qAdminAddr_,
                      address underlyingAddr_,
                      uint maturity_,
                      string memory name_,
                      string memory symbol_
                      ) public initializer {
    _name = name_;
    _symbol = symbol_;
    _qAdmin = IQAdmin(qAdminAddr_);
    _underlying = IERC20(underlyingAddr_);
    _maturity = maturity_;
  }
  
  /// @notice Needed for native token operation when withdrawing from WETH
  receive() external payable {
    // If it is not from WETH, refund it back to sender
    if (msg.sender != _qAdmin.WETH()) {
      Utils.refundExcessiveETH(0);
    }
  }
  
  modifier onlyAdmin() {
    if (!_qAdmin.hasRole(_qAdmin.ADMIN_ROLE(), msg.sender)) {
      revert CustomErrors.FRM_OnlyAdmin();
    }
    _;
  }
  
  modifier onlyQToken() {
    if (address(_qToken) != msg.sender) {
      revert CustomErrors.FRM_OnlyQToken();
    }
    _;
  }
  
  modifier onlyQuoteManager() {
    if (address(_quoteManager) != msg.sender) {
      revert CustomErrors.FRM_OnlyQuoteManager();
    }
    _;
  }

  /// @notice Modifier which checks that contract and specified operation is not paused
  modifier whenNotPaused(uint operationId) {
    if (_qAdmin.isPaused(address(this), operationId)) {
      revert CustomErrors.FRM_OperationPaused(operationId);
    }
    _;
  }
  
  /// @notice Logic copied from `@openzeppelin/contracts/security/ReentrancyGuard.sol`
  /// Reconstruct here instead of inheritance is to avoid storage slot sequence problem during
  /// contract upgrade
  modifier nonReentrant() {
    // On the first call to nonReentrant, _notEntered will be true
    if (_status == _ENTERED) {
      revert CustomErrors.FRM_ReentrancyDetected();
    }

    // Any calls to nonReentrant after this point will fail
    _status = _ENTERED;

    _;

    // By storing the original value once again, a refund is triggered (see
    // https://eips.ethereum.org/EIPS/eip-2200)
    _status = _NOT_ENTERED;
  }

  
  /** ADMIN FUNCTIONS **/
  
  // Temporal function to fix existing markets
  function _setName(string calldata name_) external onlyAdmin {
    _name = name_;
  }
  
  // Temporal function to fix existing markets
  function _setSymbol(string calldata symbol_) external onlyAdmin {
    _symbol = symbol_;
  }
  
  /// @notice Call upon initialization after deploying `QuoteManager` contract
  /// @param quoteManagerAddress Address of `QuoteManager` deployment
  function _setQuoteManager(address quoteManagerAddress) external onlyAdmin {
    // Initialize the value
    _quoteManager = IQuoteManager(quoteManagerAddress);

    // Emit the event
    emit SetQuoteManager(quoteManagerAddress);
  }
  
  /// @notice Call upon initialization after deploying `QToken` contract
  /// @param qTokenAddress Address of `QToken` deployment
  function _setQToken(address qTokenAddress) external onlyAdmin {
    // Initialize the value
    _qToken = IQToken(qTokenAddress);

    // Emit the event
    emit SetQToken(qTokenAddress);
  }
  
  /// @notice Function to be used by qToken contract to transfer native or underlying token to recipient
  /// Transfer operation is centralized in FixedRateMarket so token held does not need to be transferred
  /// to/from qToken contract.
  /// @param receiver Account of the receiver
  /// @param amount Size of the fund to be transferred from sender to receiver
  /// @param isSendingETH Indicate if sender is sending fund with ETH
  /// @param isReceivingETH Indicate if receiver is receiving fund with ETH
  function _transferTokenOrETH(
                               address receiver,
                               uint amount,
                               bool isSendingETH,
                               bool isReceivingETH
                               ) external onlyQToken {
    Utils.transferTokenOrETH(address(this), receiver, amount, _underlying, _qAdmin.WETH(), isSendingETH, isReceivingETH);
  }
  
  /// @notice Borrower will make repayments to the smart contract, which
  /// holds the value in escrow until maturity to release to lenders.
  /// @param to Address of the receiver
  /// @param amount Amount to repay
  /// @return uint Remaining account borrow amount
  function _repayBorrowInQToken(address to, uint amount) external onlyQToken nonReentrant whenNotPaused(303) returns(uint) {
    return _repayBorrow(to, amount, false, true);
  }
  
  function _updateLiquidityEmissionsOnRedeem(uint8 side, uint64 id) external onlyQToken {
    return _updateLiquidityEmissions(side, id);
  }
  
  /// @notice Call upon quote creation
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  function _onCreateQuote(uint8 side, uint64 id) external onlyQuoteManager {
    _updateLiquidityEmissions(side, id);
  }
  
  /// @notice Call upon quote fill
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  function _onFillQuote(uint8 side, uint64 id) external onlyQuoteManager {
    _updateLiquidityEmissions(side, id);
  }
  
  /// @notice Call upon quote cancellation
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  function _onCancelQuote(uint8 side, uint64 id) external onlyQuoteManager {
    _updateLiquidityEmissions(side, id);
  }
  
  /** USER INTERFACE **/

  /// @notice Creates a new  `Quote` and adds it to the `OrderbookSide` linked list by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quoteType 0 for PV+APR, 1 for FV+APR
  /// @param APR In decimal form scaled by 1e4 (ex. 1052 = 10.52%)
  /// @param cashflow Can be PV or FV depending on `quoteType`
  function createQuote(uint8 side, uint8 quoteType, uint64 APR, uint cashflow) external {
    _quoteManager.createQuote(side, msg.sender, quoteType, APR, cashflow);
  }
  
  /// @notice Analogue of market order to borrow against current lend `Quote`s.
  /// Only fills at most up to `amountPV`, any unfilled amount is discarded.
  /// @param amountPV The maximum amount to borrow
  /// @param maxAPR Only accept `Quote`s up to specified APR. You may think of
  /// this as a maximum slippage tolerance variable
  function borrow(uint amountPV, uint64 maxAPR) external nonReentrant whenNotPaused(301) {
    _execMarketOrder(_SIDE_LEND, msg.sender, amountPV, maxAPR, false);
  }
  
  /// @notice Analogue of market order to borrow against current lend `Quote`s.
  /// Only fills at most up to `amountPV`, any unfilled amount is discarded.
  /// ETH will be sent to borrower
  /// @param amountPV The maximum amount to borrow
  /// @param maxAPR Only accept `Quote`s up to specified APR. You may think of
  /// this as a maximum slippage tolerance variable
  function borrowETH(uint amountPV, uint64 maxAPR) external nonReentrant whenNotPaused(301) {
    if (address(_underlying) != _qAdmin.WETH()) {
      revert CustomErrors.FRM_EthOperationNotPermitted();
    }
    _execMarketOrder(_SIDE_LEND, msg.sender, amountPV, maxAPR, true);
  }

  /// @notice Analogue of market order to lend against current borrow `Quote`s.
  /// Only fills at most up to `amountPV`, any unfilled amount is discarded.
  /// @param amountPV The maximum amount to lend
  /// @param minAPR Only accept `Quote`s up to specified APR. You may think of
  /// this as a maximum slippage tolerance variable
  function lend(uint amountPV, uint64 minAPR) external nonReentrant whenNotPaused(302) {
    _execMarketOrder(_SIDE_BORROW, msg.sender, amountPV, minAPR, false);
  }
  
  /// @notice Analogue of market order to lend against current borrow `Quote`s.
  /// Only fills at most up to `msg.value`, any unfilled amount is discarded.
  /// Excessive amount will be sent back to lender
  /// Note that protocol fee should also be included as ETH sent in the function call
  /// @param minAPR Only accept `Quote`s up to specified APR. You may think of
  /// this as a maximum slippage tolerance variable
  function lendETH(uint64 minAPR) external payable nonReentrant whenNotPaused(302) {
    if (address(_underlying) != _qAdmin.WETH()) {
      revert CustomErrors.FRM_EthOperationNotPermitted();
    }
    
    // Deduce corresponding amountPV if protocol fee is not included 
    uint amountPV = hypotheticalMaxLendPV(msg.value);
    
    uint executedPV = _execMarketOrder(_SIDE_BORROW, msg.sender, amountPV, minAPR, true);

    Utils.refundExcessiveETH(executedPV + proratedProtocolFee(executedPV));
  }

  /// @notice Borrower will make repayments to the smart contract, which
  /// holds the value in escrow until maturity to release to lenders.
  /// @param amount Amount to repay
  /// @return uint Remaining account borrow amount
  function repayBorrow(uint amount) external nonReentrant whenNotPaused(303) returns(uint) {
    return _repayBorrow(msg.sender, amount, false, false);
  }
  
  /// @notice Borrower will make repayments to the smart contract using ETH, which
  /// holds the value in escrow until maturity to release to lenders.
  /// @return uint Remaining account borrow amount
  function repayBorrowWithETH() external payable nonReentrant whenNotPaused(303) returns(uint) {
    if (address(_underlying) != _qAdmin.WETH()) {
      revert CustomErrors.FRM_EthOperationNotPermitted();
    }
    uint balanceBefore = _accountBorrows[msg.sender];
    uint balanceAfter = _repayBorrow(msg.sender, msg.value, true, false);
    Utils.refundExcessiveETH(balanceBefore - balanceAfter);
    return balanceAfter;
  }
  
  /// @notice Cancel `Quote` by id. Note this is a O(1) operation
  /// since `OrderbookSide` uses hashmaps under the hood. However, it is
  /// O(n) against the array of `Quote` ids by account so we should ensure
  /// that array should not grow too large in practice.
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  function cancelQuote(uint8 side, uint64 id) external {
    _quoteManager.cancelQuote(true, side, msg.sender, id);
  }
  
  /// @notice If an account is in danger of being underwater (i.e. collateralRatio < 1.0)
  /// or has not repaid past maturity plus `_repaymentGracePeriod`, any user may
  /// liquidate that account by paying back the loan on behalf of the account. In return,
  /// the liquidator receives collateral belonging to the account equal in value to
  /// the repayment amount in USD plus the liquidation incentive amount as a bonus.
  /// @param borrower Address of account to liquidate
  /// @param amount Amount to repay on behalf of account in the currency of the loan
  /// @param collateralToken Liquidator's choice of which currency to be paid in
  function liquidateBorrow(address borrower, uint amount, IERC20 collateralToken) external nonReentrant whenNotPaused(305) {
    _liquidateBorrow(borrower, amount, collateralToken, false);
  }
  
  
  /** VIEW FUNCTIONS **/
  
  /// @notice Get the name of this contract
  /// @return address contract name
  function name() external view returns(string memory) {
    return _name;
  }
  
  /// @notice Get the symbol representing this contract
  /// @return address contract symbol
  function symbol() external view returns(string memory) {
    return _symbol;
  }

  /// @notice Get the address of the `QAdmin`
  /// @return address
  function qAdmin() external view returns(address) {
    return address(_qAdmin);
  }
  
  /// @notice Get the address of the `QollateralManager`
  /// @return address
  function qollateralManager() external view returns(address){
    return _qAdmin.qollateralManager();
  }
  
  /// @notice Get the address of the `QuoteManager`
  /// @return address
  function quoteManager() external view returns(address){
    return address(_quoteManager);
  }
  
  /// @notice Get the address of the `QToken`
  /// @return address
  function qToken() external view returns(address) {
    return address(_qToken);
  }

  /// @notice Get the address of the ERC20 token which the loan will be denominated
  /// @return IERC20
  function underlyingToken() external view returns(IERC20) {
    return _underlying;
  }
  
  /// @notice Get the UNIX timestamp (in seconds) when the market matures
  /// @return uint
  function maturity() external view returns(uint){
    return _maturity;
  }

  /// @notice Get the minimum quote size for this market
  /// @return uint Minimum quote size, in PV terms, local currency
  function minQuoteSize() external view returns(uint) {
    return _qAdmin.minQuoteSize(address(this));
  }

  /// @notice Get the total balance of borrows by user
  /// @param account Account to query
  /// @return uint Borrows
  function accountBorrows(address account) external view returns(uint){
    return _accountBorrows[account];
  }

  /// @notice Get the linked list pointer top of book for `Quote` by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return uint64 id of top of book `Quote` 
  function getQuoteHeadId(uint8 side) external view returns(uint64) {
    return _quoteManager.getQuoteHeadId(side);
  }

  /// @notice Get the top of book for `Quote` by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return QTypes.Quote head `Quote`
  function getQuoteHead(uint8 side) external view returns(QTypes.Quote memory) {
    return _quoteManager.getQuoteHead(side);
  }
  
  /// @notice Get the `Quote` for the given `side` and `id`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of `Quote`
  /// @return QTypes.Quote `Quote` associated with the id
  function getQuote(uint8 side, uint64 id) external view returns(QTypes.Quote memory) {
    return _quoteManager.getQuote(side, id);
  }

  /// @notice Get all live `Quote` id's by `account` and `side`
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param account Account to query
  /// @return uint[] Unsorted array of borrow `Quote` id's
  function getAccountQuotes(uint8 side, address account) external view returns(uint64[] memory) {
    return _quoteManager.getAccountQuotes(side, account);
  }

  /// @notice Get the number of active `Quote`s by `side` in the orderbook
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return uint Number of `Quote`s
  function getNumQuotes(uint8 side) external view returns(uint) {
    return _quoteManager.getNumQuotes(side);
  }
    
  /// @notice Gets the `protocolFee` associated with this market
  /// @return uint annualized protocol fee, scaled by 1e4
  function protocolFee() public view returns(uint) {
    // If fee emissions qontroller is not defined, no protocol fee will be charged
    if (address(_qAdmin.feeEmissionsQontroller()) == address(0)) {
      return 0;
    }
    return _qAdmin.protocolFee(address(this));
  }

  /// @notice Gets the `protocolFee` associated with this market, prorated by time till maturity 
  /// @param amount loan amount
  /// @return uint prorated protocol fee in local currency
  function proratedProtocolFee(uint amount) public view returns(uint) {
    return proratedProtocolFee(amount, block.timestamp);
  }

  /// @notice Gets the `protocolFee` associated with this market, prorated by time till maturity 
  /// @param amount loan amount
  /// @param timestamp UNIX timestamp in seconds
  /// @return uint prorated protocol fee in local currency
  function proratedProtocolFee(uint amount, uint timestamp) public view returns(uint) {
    if (timestamp >= _maturity) {
      revert CustomErrors.FRM_MarketExpired();
    }
    return amount * protocolFee() * (_maturity - timestamp) / _qAdmin.MANTISSA_BPS() / ONE_YEAR_IN_SECONDS;
  }
  
  /// @notice Get total protocol fee accrued in this market so far, in local currency
  /// @return uint accrued fee
  function totalAccruedFees() external view returns(uint) {
    return _totalAccruedFees;
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
    return _quoteManager.getPV(quoteType, APR, amount, sTime, eTime);
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
    return _quoteManager.getFV(quoteType, APR, amount, sTime, eTime);    
  }
  
  /// @notice Get maximum value user can lend with given amount when protocol fee is factored in.
  /// Mantissa is added to reduce precision error during calculation
  /// @param amount Lending amount with protocol fee factored in
  /// @return uint Maximum value user can lend with protocol fee considered
  function hypotheticalMaxLendPV(uint amount) public view returns (uint) {
    // Round up denominator if it is not fully divisible
    uint num = amount * 1e18;
    uint denom = 1e18 + proratedProtocolFee(1e18);
    return num / (denom + Math.min(num % denom, 1)); 
  }
  
  
  /** INTERNAL FUNCTIONS **/

  /// @notice Called under the hood by external `borrow` and `lend` functions.
  /// This function loops through the opposite `OrderbookSide`, executing loans
  /// until either the full amount is filled, the `OrderbookSide` is empty, or
  /// no more `Quote`s exist that satisfy the `limitAPR` set by the market order.
  /// @param quoteSide 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param account Address of the `Acceptor`
  /// @param amountPV Amount that the `Acceptor` wants to execute, as PV
  /// @param limitAPR Only accept `Quote`s up to specified APR. You may think of
  /// this as a maximum slippage tolerance variable
  /// @param isPaidInETH Is amount being paid in ETH
  /// @return uint Total amount executed in PV terms
  function _execMarketOrder(
                            uint8 quoteSide,
                            address account,
                            uint amountPV,
                            uint64 limitAPR,
                            bool isPaidInETH
                            ) internal returns (uint) {

    // Store the initial requested `Acceptor` size - must be positive
    if (amountPV <= 0) {
      revert CustomErrors.FRM_AmountZero();
    }
    uint amountRemaining = amountPV;

    // Start `Quote`s from head
    QTypes.Quote memory currQuote = _quoteManager.getQuoteHead(quoteSide);

    uint totalExecutedPV = 0;
    uint totalExecutedFV = 0;
    
    while(amountRemaining > 0) {
      
      if((quoteSide == _SIDE_LEND && limitAPR < currQuote.APR) ||
         (quoteSide == _SIDE_BORROW && limitAPR > currQuote.APR)) {
        
        // Stop loop condition: `limitAPR` works as a limit price.
        // Since `Quote`s are ordered by APR, if the current `Quote` is past
        // the limit, we know all remaining `Quote`s will not satisfy the
        // `Acceptor`s conditions
        break;

      } else if(currQuote.id == _NULL_POINTER) {

        // Stop loop condition: No more `Quote`s remaining
        break;

      } else if(account == currQuote.quoter) {

        // Cannot execute `Quote` against self - just ignore it
        // Move to the next `Quote` in line
        currQuote = _quoteManager.getQuote(quoteSide, currQuote.next);

      } else if(!_quoteManager.isQuoteValid(quoteSide, currQuote)) {

        // Store the pointer to the next best `Quote`
        uint64 next = currQuote.next;

        // Clean up invalid `Quote`s. If the current `Quote` is not valid, it
        // will be cancelled automatically without notice to the creator of
        // the `Quote`
        _quoteManager.cancelQuote(false, quoteSide, currQuote.quoter, currQuote.id);

        // Move to the next `Quote` in line
        currQuote = _quoteManager.getQuote(quoteSide, next);        

      } else {

        // `Quote` is valid. Preprocess and then execute the loan
        (uint execAmountPV, uint execAmountFV) = _preprocessLoan(quoteSide, currQuote.id, account, amountRemaining, isPaidInETH);
        totalExecutedPV += execAmountPV;
        totalExecutedFV += execAmountFV;
        
        // Just in case of potential rounding errors, floor the new `amountRemaining` at zero
        if(amountRemaining > execAmountPV) {
          amountRemaining = amountRemaining - execAmountPV;
        } else {
          amountRemaining = 0;
        }

        // Move to the next `Quote` in line
        currQuote = _quoteManager.getQuote(quoteSide, currQuote.next);
      }      
    }
    if (totalExecutedPV > 0) {
      emit ExecMarketOrder(quoteSide, account, totalExecutedPV, totalExecutedFV);
    }
    return totalExecutedPV;
  }

  /// @notice Intermediary function that handles order/quote sides, PV/FV
  /// and actual executed amount calculations, and updates `Quote` fill status
  /// @param quoteSide 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quoteId Id of the `Quote`
  /// @param acceptor Address of the `Acceptor`
  /// @param acceptorAmountPV Amount that the `Acceptor` wants to execute, as PV
  /// @param isPaidInETH Is amount being paid in ETH
  /// @return uint execAmountPV uint execAmountFV
  function _preprocessLoan(
                           uint8 quoteSide,
                           uint64 quoteId,
                           address acceptor,
                           uint acceptorAmountPV,
                           bool isPaidInETH
                           ) internal returns(uint,uint){

    // Get immutable instance of `Quote`
    QTypes.Quote memory quote = _quoteManager.getQuote(quoteSide, quoteId);
    
    uint execAmountPV;
    uint execAmountFV;
    if(quote.quoteType == 0){ // Quote is in PV terms

      // Executing Amount must be the smaller of the `Quoter` and `Acceptor` size
      execAmountPV = Math.min(acceptorAmountPV, quote.cashflow - quote.filled);

      // Get the equivalent executed amount in PV terms
      execAmountFV = Interest.PVToFV(
                                     quote.APR,
                                     execAmountPV,
                                     block.timestamp,
                                     _maturity,
                                     _qAdmin.MANTISSA_BPS()
                                     );

      // Update the filled amount for the `Quote`
      quote.filled += execAmountPV;
      _quoteManager.fillQuote(quoteSide, quoteId, execAmountPV);
      
    }else { // Quote is in FV terms
      
      // Get the equivalent FV amount of Acceptor's original amount
      uint acceptorAmountFV = Interest.PVToFV(
                                              quote.APR,
                                              acceptorAmountPV,
                                              block.timestamp,
                                              _maturity,
                                              _qAdmin.MANTISSA_BPS()
                                              );      

      // Executing Amount must be the smaller of the `Quoter` and `Acceptor` size
      execAmountFV = Math.min(acceptorAmountFV, quote.cashflow - quote.filled);

      // Get the equivalent executed amount in PV terms
      execAmountPV = Interest.FVToPV(
                                     quote.APR,
                                     execAmountFV,
                                     block.timestamp,
                                     _maturity,
                                     _qAdmin.MANTISSA_BPS()
                                     );

      // Update the filled amount for the `Quote`
      quote.filled += execAmountFV;
      _quoteManager.fillQuote(quoteSide, quoteId, execAmountFV);
      
    }

    address quoter = quote.quoter;
    uint64 apr = quote.APR;
    if (quote.cashflow - quote.filled < _DUST) {
      // If `Quote` is fully filled (minus dust), remove it from the `OrderbookSide`
      _quoteManager.cancelQuote(false, quoteSide, quote.quoter, quote.id);
    }
    
    // Create the loan, taking care to differentiate whether the `Quoter` is the
    // lender and `Acceptor` is the borrower, or vice versa
    if (quoteSide == _SIDE_BORROW) {
      return _createFixedRateLoan(quoteSide, quoter, acceptor, execAmountPV, execAmountFV, proratedProtocolFee(execAmountPV), apr, isPaidInETH);
    } 
    if (quoteSide == _SIDE_LEND) {
      return _createFixedRateLoan(quoteSide, acceptor, quoter, execAmountPV, execAmountFV, proratedProtocolFee(execAmountPV), apr, isPaidInETH);
    } 
    revert CustomErrors.FRM_InvalidSide();
  }

  /// @notice Mint the future `qToken`s to the lender, add `amountFV` to the
  /// borrower's debts, transfer `amountPV` from lender to borrower, and accrue
  /// `protocolFee`s to the `FeeEmissionsQontroller`
  /// @param quoteSide 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param borrower Account of the borrower
  /// @param lender Account of the lender
  /// @param amountPV Size of the initial loan paid by lender
  /// @param amountFV Final amount that must be paid by borrower
  /// @param protocolFee_ Protocol fee to be paid by both lender and borrower in the transaction
  /// @param APR In decimal form scaled by 1e4 (ex. 10.52% = 1052)
  /// @param isPaidInETH Is amount being paid in ETH
  /// @return uint execAmountPV uint execAmountFV
  function _createFixedRateLoan(
                                uint8 quoteSide,
                                address borrower,
                                address lender,
                                uint amountPV,
                                uint amountFV,
                                uint protocolFee_,
                                uint64 APR,
                                bool isPaidInETH
                                ) internal returns(uint, uint){

    // Loan amount must be strictly positive
    if (amountPV <= 0) {
      revert CustomErrors.FRM_AmountZero();
    }

    // Interest rate needs to be positive
    if (amountPV >= amountFV) {
      revert CustomErrors.FRM_InvalidAPR();
    }

    // AmountPV should be able to cover protocolFee cost
    if (amountPV <= protocolFee_) {
      revert CustomErrors.FRM_AmountLessThanProtocolFee();
    }

    // Cannot execute loan against self
    if (lender == borrower) {
      revert CustomErrors.FRM_InvalidCounterparty();
    }

    // Cannot create a loan past its maturity time
    if (block.timestamp >= _maturity) {
      revert CustomErrors.FRM_InvalidMaturity();
    }

    // If contract is to act on behalf of lender, assume upstream has handled related fund transfer to the contract.
    // So no fund availability check is needed here.
    if (quoteSide != _SIDE_BORROW || !isPaidInETH) {
      // Check lender has approved contract spend
      if (_underlying.allowance(lender, address(this)) < amountPV + protocolFee_) {
        revert CustomErrors.FRM_InsufficientAllowance();
      }
  
      // Check lender has enough balance
      if (_underlying.balanceOf(lender) < amountPV + protocolFee_) {
        revert CustomErrors.FRM_InsufficientBalance();
      }
    }

    // Check if borrowing amount is above max borrow and update market participated  
    _checkRatioAndAddParticipatedMarket(borrower, lender, amountFV);
    
    // The borrow amount of the borrower increases by the full `amountFV`
    _accountBorrows[borrower] += amountFV;
    
    // Net off borrow amount with any balance of qTokens the borrower may have
    _repayBorrow(borrower, _qToken.balanceOf(borrower), false, true);

    // Transfer `amountPV` from lender to borrower, and protocolFee from both
    // lender and borrower to `FeeEmissionsQontroller`.
    // Note that lender will pay `protocolFee_` from their account balance,
    // while borrower will pay `protocolFee_` from their borrowed amount. So
    // total amount involved in transfer = amountPV + protocolFee_
    // Also note that if it is WETH market and borrower intends to receive ETH,
    // contract will receive on behalf and do token unwrapping outside this function
    IFeeEmissionsQontroller feq = IFeeEmissionsQontroller(_qAdmin.feeEmissionsQontroller());
    bool lenderInitiate = quoteSide == _SIDE_BORROW;
    if (address(feq) == address(0)) {
      Utils.transferTokenOrETH(lender, borrower, amountPV, _underlying, _qAdmin.WETH(), isPaidInETH && lenderInitiate, isPaidInETH && !lenderInitiate);
    } else {
      // No token unwrapping is need for FeeEmissionsQontroller as target recipient
      Utils.transferTokenOrETH(lender, address(feq), protocolFee_ * 2, _underlying, _qAdmin.WETH(), isPaidInETH && lenderInitiate, false);
      Utils.transferTokenOrETH(lender, borrower, amountPV - protocolFee_, _underlying, _qAdmin.WETH(), isPaidInETH && lenderInitiate, isPaidInETH && !lenderInitiate);

      _totalAccruedFees += protocolFee_ * 2;
      feq.receiveFees(_underlying, protocolFee_ * 2);
    }

    // Lender receives `amountFV` amount in qTokens
    // Put this last to protect against reentracy
    _qToken.mint(lender, amountFV);
    
    // Net off the minted amount with any borrow amounts the lender may have
    _repayBorrow(lender, _qToken.balanceOf(lender), false, true);

    // Finally, report trading volumes for trading rewards
    _updateTradingRewards(borrower, lender, amountPV);

    // Emit the matched borrower and lender and fixed rate loan terms
    emit FixedRateLoan(quoteSide, borrower, lender, amountPV, amountFV, protocolFee_, APR);

    return (amountPV, amountFV);
  }
  
  /// @notice Check if borrowing amount is breaching maximum allow amount borrow,
  /// which is determined by initCollateralRatio and creditLimit.
  /// Note `_initCollateralRatio` is a larger value than `_minCollateralRatio`. 
  /// This protects users from taking loans at the minimum threshold, 
  /// putting them at risk of instant liquidation.
  /// @param borrower Account of the borrower
  /// @param lender Account of the lender
  /// @param amountFV Final amount that must be paid by borrower
  function _checkRatioAndAddParticipatedMarket(address borrower, address lender, uint amountFV) internal {
    IQollateralManager qm = IQollateralManager(_qAdmin.qollateralManager());
    IFixedRateMarket currentMarket = IFixedRateMarket(address(this));
    uint maxBorrowFV = qm.hypotheticalMaxBorrowFV(borrower, currentMarket);
    if (amountFV > maxBorrowFV) {
      revert CustomErrors.FRM_MaxBorrowExceeded();
    }

    // Record that the lender/borrow have participated in this market
    if(!qm.accountMarkets(lender, currentMarket)){
      qm._addAccountMarket(lender, currentMarket);
    }
    if(!qm.accountMarkets(borrower, currentMarket)){
      qm._addAccountMarket(borrower, currentMarket);
    }
  }
  
  /// @notice Borrower will make repayments to the smart contract, which
  /// holds the value in escrow until maturity to release to lenders.
  /// @param amount Amount to repay
  /// @param isPaidInETH Is amount being paid in ETH
  /// @param isPaidInQTokens Is amount being paid with qTokens
  /// @return uint Remaining account borrow amount
  function _repayBorrow(address account, uint amount, bool isPaidInETH, bool isPaidInQTokens) internal returns(uint){

    // Don't allow users to pay more than necessary
    amount = Math.min(amount, _accountBorrows[account]);
    
    if (isPaidInQTokens) {
      if(amount == 0) {      
        // Short-circuit: If user has no qTokens, no need to do anything
        return _accountBorrows[account];
      }
      
      // Burn the qTokens from the account and subtract the amount for the user's borrows
      _qToken.burn(account, amount);
    } else {
      // Repayment amount must be positive
      if (amount <= 0) {
        revert CustomErrors.FRM_AmountZero();
      }
      
      // Transfer amount from borrower to contract for escrow until maturity
      uint balanceBefore = _underlying.balanceOf(address(this));
      Utils.transferTokenOrETH(account, address(this), amount, _underlying, _qAdmin.WETH(), isPaidInETH, false);
      amount = _underlying.balanceOf(address(this)) - balanceBefore;
    }

    // Deduct from the account's total debts
    // Guaranteed not to underflow due to the flooring on amount above
    _accountBorrows[account] -= amount;
    
    // Emit the event
    emit RepayBorrow(account, amount, isPaidInQTokens);

    return _accountBorrows[account];
  }
  
  /// @notice If an account is in danger of being underwater (i.e. collateralRatio < 1.0)
  /// or has not repaid past maturity plus `_repaymentGracePeriod`, any user may
  /// liquidate that account by paying back the loan on behalf of the account. In return,
  /// the liquidator receives collateral belonging to the account equal in value to
  /// the repayment amount in USD plus the liquidation incentive amount as a bonus.
  /// @param borrower Address of account to liquidate
  /// @param amount Amount to repay on behalf of account in the currency of the loan
  /// @param collateralToken Liquidator's choice of which currency to be paid in
  /// @param isPaidInETH Is amount being paid in ETH
  /// @return uint Amount transferred for liquidation
  function _liquidateBorrow(address borrower, uint amount, IERC20 collateralToken, bool isPaidInETH) internal returns(uint) {

    IQollateralManager qm = IQollateralManager(_qAdmin.qollateralManager());
    uint repaymentGracePeriod = _qAdmin.repaymentGracePeriod();

    // Ensure borrower is either underwater or past payment due date.
    // These are the necessary conditions before borrower can be liquidated.
    if (qm.collateralRatio(borrower) >= _qAdmin.minCollateralRatio(borrower) &&
        block.timestamp <= _maturity + repaymentGracePeriod) {
      revert CustomErrors.FRM_NotLiquidatable();
    }
    
    // For borrowers that are underwater, liquidator can only repay up
    // to a percentage of the full loan balance determined by the `closeFactor`
    uint closeFactor = qm.closeFactor();
    
    // For borrowers that are past due date, ignore the close factor - liquidator
    // can liquidate the entire sum
    if(block.timestamp > _maturity){
      closeFactor = _qAdmin.MANTISSA_FACTORS();
    }

    // Liquidator cannot repay more than the percentage of the full loan balance
    // determined by `closeFactor`
    uint maxRepayment = _accountBorrows[borrower] * closeFactor / _qAdmin.MANTISSA_FACTORS();
    amount = Math.min(amount, maxRepayment);

    // Amount must be positive
    if (amount <= 0) {
      revert CustomErrors.FRM_AmountZero();
    }

    // Get USD value of amount paid
    uint amountUSD = qm.localToUSD(_underlying, amount);

    // Get USD value of amount plus liquidity incentive
    uint rewardUSD = amountUSD * _qAdmin.liquidationIncentive() / _qAdmin.MANTISSA_FACTORS();

    // Get the local amount of collateral to reward liquidator
    uint rewardLocal = qm.USDToLocal(collateralToken, rewardUSD);

    // Ensure the borrower has enough collateral balance to pay the liquidator
    if (rewardLocal > qm.collateralBalance(borrower, collateralToken)) {
      revert CustomErrors.FRM_NotEnoughCollateral();
    }

    // Liquidator repays the loan on behalf of borrower
    Utils.transferTokenOrETH(msg.sender, address(this), amount, _underlying, _qAdmin.WETH(), isPaidInETH, false);

    // Credit the borrower's account
    _accountBorrows[borrower] -= amount;

    // Emit the event
    emit LiquidateBorrow(borrower, msg.sender, amount, address(collateralToken), rewardLocal);

    // Transfer the collateral balance from borrower to the liquidator
    qm._transferCollateral(collateralToken, borrower, msg.sender, rewardLocal);
    
    // Return amount transferred for liquidation
    return amount;
  }
  
  /// @notice Tracks the amount traded, its associated protocol fees, normalize
  /// to USD, and reports the data to `TradingEmissionsQontroller` which handles
  /// disbursing token rewards for trading volumes
  /// @param borrower Address of the borrower
  /// @param lender Address of the lender
  /// @param amountPV Amount traded (in local currency, in PV terms)
  function _updateTradingRewards(address borrower, address lender, uint amountPV) internal {
    // Instantiate interfaces
    ITradingEmissionsQontroller teq = ITradingEmissionsQontroller(_qAdmin.tradingEmissionsQontroller());
    
    if (address(teq) != address(0)) {
      
      IQPriceOracle oracle = IQPriceOracle(_qAdmin.qPriceOracle());

      // Get the associated protocol fees generated by the amount
      uint feeLocal = proratedProtocolFee(amountPV);
    
      // Convert the fee to USD
      uint feeUSD = oracle.localToUSD(_underlying, feeLocal);
        
      // report volumes to `TradingEmissionsQontroller`
      teq.updateRewards(borrower, lender, feeUSD);
    }
  }
  
  function _updateLiquidityEmissions(uint8 side, uint64 id) internal {
    address liquidityEmissionsAddress = _qAdmin.liquidityEmissionsQontroller();
    if (liquidityEmissionsAddress != address(0)) {
      ILiquidityEmissionsQontroller qontroller = ILiquidityEmissionsQontroller(liquidityEmissionsAddress);
      uint lastDistributeTime = qontroller.lastDistributeTime(address(this), side);
      if (lastDistributeTime > 0 && lastDistributeTime < _maturity) {
        qontroller.updateRewards(this, side, id);
      }
    }
  }

}

