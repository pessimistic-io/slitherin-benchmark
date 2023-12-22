//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9 <=0.8.19;

import "./IERC20.sol";
import "./QTypes.sol";

interface IFixedRateMarket {
  
  /// @notice Emitted when market order is created and loan can be created with one or more quotes
  event ExecMarketOrder(
                        uint8 indexed quoteSide,
                        address indexed account,
                        uint totalExecutedPV,
                        uint totalExecutedFV
                        );
  
  /// @notice Emitted when a borrower repays borrow.
  /// Boolean flag `withQTokens`= true if repaid via qTokens, false otherwise.
  event RepayBorrow(address indexed borrower, uint amount, bool withQTokens);
  
  /// @notice Emitted when a borrower is liquidated
  event LiquidateBorrow(
                        address indexed borrower,
                        address indexed liquidator,
                        uint amount,
                        address collateralTokenAddr,
                        uint reward
                        );
  
  /// @notice Emitted when a borrower and lender are matched for a fixed rate loan
  event FixedRateLoan(
                      uint8 indexed quoteSide,
                      address indexed borrower,
                      address indexed lender,
                      uint amountPV,
                      uint amountFV,
                      uint feeIncurred,
                      uint64 APR
                      );
    
  /// @notice Emitted when setting `_quoteManager`
  event SetQuoteManager(address quoteManagerAddress);
  
  /// @notice Emitted when setting `_qToken`
  event SetQToken(address qTokenAddress);

  /** ADMIN FUNCTIONS **/
  
  /// @notice Call upon initialization after deploying `QuoteManager` contract
  /// @param quoteManagerAddress Address of `QuoteManager` deployment
  function _setQuoteManager(address quoteManagerAddress) external;
    
  /// @notice Call upon initialization after deploying `QToken` contract
  /// @param qTokenAddress Address of `QToken` deployment
  function _setQToken(address qTokenAddress) external;
  
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
                               ) external;
  
  /// @notice Borrower will make repayments to the smart contract, which
  /// holds the value in escrow until maturity to release to lenders.
  /// @param to Address of the receiver
  /// @param amount Amount to repay
  /// @return uint Remaining account borrow amount
  function _repayBorrowInQToken(address to, uint amount) external returns(uint);
  
  function _updateLiquidityEmissionsOnRedeem(uint8 side, uint64 id) external;
  
  /// @notice Call upon quote creation
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  function _onCreateQuote(uint8 side, uint64 id) external;
    
  /// @notice Call upon quote fill
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  function _onFillQuote(uint8 side, uint64 id) external;
    
  /// @notice Call upon quote cancellation
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  function _onCancelQuote(uint8 side, uint64 id) external;
  
  /** USER INTERFACE **/
  
  /// @notice Creates a new  `Quote` and adds it to the `OrderbookSide` linked list by side
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param quoteType 0 for PV+APR, 1 for FV+APR
  /// @param APR In decimal form scaled by 1e4 (ex. 1052 = 10.52%)
  /// @param cashflow Can be PV or FV depending on `quoteType`
  function createQuote(uint8 side, uint8 quoteType, uint64 APR, uint cashflow) external;
  
  /// @notice Analogue of market order to borrow against current lend `Quote`s.
  /// Only fills at most up to `amountPV`, any unfilled amount is discarded.
  /// @param amountPV The maximum amount to borrow
  /// @param maxAPR Only accept `Quote`s up to specified APR. You may think of
  /// this as a maximum slippage tolerance variable
  function borrow(uint amountPV, uint64 maxAPR) external;
    
  /// @notice Analogue of market order to borrow against current lend `Quote`s.
  /// Only fills at most up to `amountPV`, any unfilled amount is discarded.
  /// ETH will be sent to borrower
  /// @param amountPV The maximum amount to borrow
  /// @param maxAPR Only accept `Quote`s up to specified APR. You may think of
  /// this as a maximum slippage tolerance variable
  function borrowETH(uint amountPV, uint64 maxAPR) external;

  /// @notice Analogue of market order to lend against current borrow `Quote`s.
  /// Only fills at most up to `amountPV`, any unfilled amount is discarded.
  /// @param amountPV The maximum amount to lend
  /// @param minAPR Only accept `Quote`s up to specified APR. You may think of
  /// this as a maximum slippage tolerance variable
  function lend(uint amountPV, uint64 minAPR) external;
    
  /// @notice Analogue of market order to lend against current borrow `Quote`s.
  /// Only fills at most up to `msg.value`, any unfilled amount is discarded.
  /// Excessive amount will be sent back to lender
  /// Note that protocol fee should also be included as ETH sent in the function call
  /// @param minAPR Only accept `Quote`s up to specified APR. You may think of
  /// this as a maximum slippage tolerance variable
  function lendETH(uint64 minAPR) external payable;

  /// @notice Borrower will make repayments to the smart contract, which
  /// holds the value in escrow until maturity to release to lenders.
  /// @param amount Amount to repay
  /// @return uint Remaining account borrow amount
  function repayBorrow(uint amount) external returns(uint);
  
  /// @notice Borrower will make repayments to the smart contract using ETH, which
  /// holds the value in escrow until maturity to release to lenders.
  /// @return uint Remaining account borrow amount
  function repayBorrowWithETH() external payable returns(uint);
  
  /// @notice Cancel `Quote` by id. Note this is a O(1) operation
  /// since `OrderbookSide` uses hashmaps under the hood. However, it is
  /// O(n) against the array of `Quote` ids by account so we should ensure
  /// that array should not grow too large in practice.
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param id Id of the `Quote`
  function cancelQuote(uint8 side, uint64 id) external;

  /// @notice If an account is in danger of being underwater (i.e. collateralRatio < 1.0)
  /// or has not repaid past maturity plus `_repaymentGracePeriod`, any user may
  /// liquidate that account by paying back the loan on behalf of the account. In return,
  /// the liquidator receives collateral belonging to the account equal in value to
  /// the repayment amount in USD plus the liquidation incentive amount as a bonus.
  /// @param borrower Address of account to liquidate
  /// @param amount Amount to repay on behalf of account in the currency of the loan
  /// @param collateralToken Liquidator's choice of which currency to be paid in
  function liquidateBorrow(address borrower, uint amount, IERC20 collateralToken) external;
    
  /** VIEW FUNCTIONS **/
  
  /// @notice Get the name of this contract
  /// @return address contract name
  function name() external view returns(string memory);
  
  /// @notice Get the symbol representing this contract
  /// @return address contract symbol
  function symbol() external view returns(string memory);

  /// @notice Get the address of the `QAdmin`
  /// @return address
  function qAdmin() external view returns(address);
  
  /// @notice Get the address of the `QollateralManager`
  /// @return address
  function qollateralManager() external view returns(address);
    
  /// @notice Get the address of the `QuoteManager`
  /// @return address
  function quoteManager() external view returns(address);
  
  /// @notice Get the address of the `QToken`
  /// @return address
  function qToken() external view returns(address);

  /// @notice Get the address of the ERC20 token which the loan will be denominated
  /// @return IERC20
  function underlyingToken() external view returns(IERC20);

  /// @notice Get the UNIX timestamp (in seconds) when the market matures
  /// @return uint
  function maturity() external view returns(uint);

  /// @notice Get the minimum quote size for this market
  /// @return uint Minimum quote size, in PV terms, local currency
  function minQuoteSize() external view returns(uint);

  /// @notice Get the total balance of borrows by user
  /// @param account Account to query
  /// @return uint Borrows
  function accountBorrows(address account) external view returns(uint);

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
    
  /// @notice Gets the `protocolFee` associated with this market
  /// @return uint annualized protocol fee, scaled by 1e4
  function protocolFee() external view returns(uint);

  /// @notice Gets the `protocolFee` associated with this market, prorated by time till maturity 
  /// @param amount loan amount
  /// @return uint prorated protocol fee in local currency
  function proratedProtocolFee(uint amount) external view returns(uint);
  
  /// @notice Gets the `protocolFee` associated with this market, prorated by time till maturity 
  /// @param amount loan amount
  /// @param timestamp UNIX timestamp in seconds
  /// @return uint prorated protocol fee in local currency
  function proratedProtocolFee(uint amount, uint timestamp) external view returns(uint);

  /// @notice Get total protocol fee accrued in this market so far, in local currency
  /// @return uint accrued fee
  function totalAccruedFees() external view returns(uint);

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

  /// @notice Get maximum value user can lend with given amount when protocol fee is factored in.
  /// Mantissa is added to reduce precision error during calculation
  /// @param amount Lending amount with protocol fee factored in
  /// @return uint Maximum value user can lend with protocol fee considered
  function hypotheticalMaxLendPV(uint amount) external view returns (uint);
  
}

