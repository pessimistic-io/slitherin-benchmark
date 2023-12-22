// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.20;

struct Config {
    address FETCHER;
    bytes32 ORACLE; // 1bit QTI, 31bit reserve, 32bit WINDOW, ... PAIR ADDRESS
    address TOKEN_R;
    uint256 K;
    uint256 MARK;
    uint256 INTEREST_HL;
    uint256 PREMIUM_HL;
    uint256 MATURITY;
    uint256 MATURITY_VEST;
    uint256 MATURITY_RATE; // x128
    uint256 OPEN_RATE;
}

struct Param {
    uint256 sideIn;
    uint256 sideOut;
    address helper;
    bytes payload;
}

struct Payment {
    address utr;
    bytes payer;
    address recipient;
}

// represent a single pool state
struct State {
    uint256 R; // pool reserve
    uint256 a; // LONG coefficient
    uint256 b; // SHORT coefficient
}

// anything that can be changed between tx construction and confirmation
struct Slippable {
    uint256 xk; // (price/MARK)^K
    uint256 R; // pool reserve
    uint256 rA; // LONG reserve
    uint256 rB; // SHORT reserve
}

interface IPool {
    function init(State memory state, Payment memory payment) external;

    function swap(
        Param memory param,
        Payment memory payment
    ) external returns (uint256 amountIn, uint256 amountOut, uint256 price);

    function loadConfig() external view returns (Config memory);
}

