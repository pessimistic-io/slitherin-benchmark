//SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.15;

error Unauthorized();
error AccrueInterestError(Error error);
error WrongParams();
error Unexpected(string error);
error InvalidCoupon();
error ControllerError(Error error);
error AdminError(Error error);
error MarketError(Error error);
error HTokenError(Error error);
error LiquidatorError(Error error);
error ControlPanelError(Error error);
error HTokenFactoryError(Error error);
error WHTokenError(Error error);
error PausedAction();
error NotOwner();
error ExternalFailure(string error);
error Initialized();
error Uninitialized();
error OracleNotUpdated();
error TransferError();
error StalePrice();
error TransferFailed(string error);
error RouterError(Error error);

/**
 * @title   Errors reported across Honey Labs Inc. contracts
 * @author  Honey Labs Inc.
 * @custom:coauthor BowTiedPickle
 * @custom:coauthor m4rio
 */
enum Error {
  UNAUTHORIZED, //0
  INSUFFICIENT_LIQUIDITY,
  INVALID_COLLATERAL_FACTOR,
  MAX_MARKETS_IN,
  MARKET_NOT_LISTED,
  MARKET_ALREADY_LISTED, //5
  MARKET_CAP_BORROW_REACHED,
  MARKET_NOT_FRESH,
  PRICE_ERROR,
  BAD_INPUT,
  AMOUNT_ZERO, //10
  NO_DEBT,
  LIQUIDATION_NOT_ALLOWED,
  WITHDRAW_NOT_ALLOWED,
  INITIAL_EXCHANGE_MANTISSA,
  TRANSFER_ERROR, //15
  COUPON_LOOKUP,
  TOKEN_INSUFFICIENT_CASH,
  BORROW_RATE_TOO_BIG,
  NONZERO_BORROW_BALANCE,
  AMOUNT_TOO_BIG, //20
  AUCTION_NOT_ACTIVE,
  AUCTION_FINISHED,
  AUCTION_NOT_FINISHED,
  AUCTION_BID_TOO_LOW,
  AUCTION_NO_BIDS, //25
  CLAWBACK_WINDOW_EXPIRED,
  CLAWBACK_WINDOW_NOT_EXPIRED,
  REFUND_NOT_OWED,
  TOKEN_LOOKUP_ERROR,
  INSUFFICIENT_WINNING_BID, //30
  TOKEN_DEBT_NONEXISTENT,
  AUCTION_SETTLE_FORBIDDEN,
  NFT20_PAIR_NOT_FOUND,
  NFTX_PAIR_NOT_FOUND,
  TOKEN_NOT_PRESENT, //35
  CANCEL_TOO_SOON,
  AUCTION_USER_NOT_FOUND,
  NOT_FOUND,
  INVALID_MAX_LTV_FACTOR,
  BALANCE_INSUFFICIENT, //40
  ORACLE_NOT_SET,
  MARKET_INVALID,
  FACTORY_INVALID_COLLATERAL,
  FACTORY_INVALID_UNDERLYING,
  FACTORY_INVALID_ORACLE, //45
  FACTORY_DEPLOYMENT_FAILED,
  REPAY_NOT_ALLOWED,
  NONZERO_UNDERLYING_BALANCE,
  INVALID_ACTION,
  ORACLE_IS_PRESENT, //50
  FACTORY_INVALID_UNDERLYING_DECIMALS,
  FACTORY_INVALID_INTEREST_RATE_MODEL,
  FACTORY_CLONE_DEPLOYMENT_FAILED,
  INVALID_TOKEN_ID,
  INSUFFICIENT_BALANCE, // 55
  INVALID_VALUE,
  INVALID_LENGTH
}

