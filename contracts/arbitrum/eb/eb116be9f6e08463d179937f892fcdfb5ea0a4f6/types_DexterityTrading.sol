// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// =================
//      ENUMS
// =================

// The order's side (Bid or Ask)
enum Side {
    BID,
    ASK
}

// The order type (supported types include Limit, FOK, IOC and PostOnly)
enum OrderType {
    LIMIT,
    IMMEDIATE_OR_CANCEL,
    FILL_OR_KILL,
    POST_ONLY
}

// Configures what happens when this order is at least partially matched against an order belonging to the same user account
enum SelfTradeBehavior {
    // The orders are matched together
    DECREMENT_TAKE,
    // The order on the provide side is cancelled. Matching for the current order continues and essentially bypasses
    // the self-provided order.
    CANCEL_PROVIDE,
    // The entire transaction fails and the program returns an error.
    ABORT_TRANSACTION
}

// =================
//     STRUCTS
// =================

// The max quantity of base token to match and post
struct Fractional {
    uint256 m;
    uint256 exp;
}

// Params for a new order
struct NewOrderParams {
    Side side;
    Fractional max_base_qty;
    OrderType order_type;
    SelfTradeBehavior self_trade_behavior;
    uint256 match_limit;
    Fractional limit_price;
}

// Accounts required
struct NewOrderAccounts {
    bytes32 user;
    bytes32 trader_risk_group;
    bytes32 market_product_group;
    bytes32 product;
    bytes32 aaob_program;
    bytes32 orderbook;
    bytes32 market_signer;
    bytes32 event_queue;
    bytes32 bids;
    bytes32 asks;
    bytes32 system_program;
    bytes32 fee_model_program;
    bytes32 fee_model_configuration_acct;
    bytes32 trader_fee_state_acct;
    bytes32 fee_output_register;
    bytes32 risk_engine_program;
    bytes32 risk_model_configuration_acct;
    bytes32 risk_output_register;
    bytes32 trader_risk_state_acct;
    bytes32 risk_and_fee_signer;
}
struct CancelOrderAccounts {
    bytes32 user;
    bytes32 trader_risk_group;
    bytes32 market_product_group;
    bytes32 product;
    bytes32 aaob_program;
    bytes32 orderbook;
    bytes32 market_signer;
    bytes32 event_queue;
    bytes32 bids;
    bytes32 asks;
    bytes32 risk_engine_program;
    bytes32 risk_model_configuration_acct;
    bytes32 risk_output_register;
    bytes32 trader_risk_state_acct;
    bytes32 risk_and_fee_signer;
}

struct CancelOrderParams {
    uint128 order_id;
    bool no_err;
}

struct DepositFundsAccounts {
    bytes32 token_program;
    bytes32 user;
    bytes32 user_token_account;
    bytes32 trader_risk_group;
    bytes32 market_product_group;
    bytes32 market_product_group_vault;
    bytes32 capital_limits;
    bytes32 whitelist_ata_acct;
}

struct DepositFundsParams {
    Fractional quantity;
}

