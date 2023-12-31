// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

library Types {
    struct D3MMState {
        // the D3vault contract
        address _D3_VAULT_;
        // the creator of pool
        address _CREATOR_;
        // maker contract address
        address _MAKER_;
        address _ORACLE_;
        address _FEE_RATE_MODEL_;
        address _MAINTAINER_;
        // token balance
        mapping(address => uint256) balances;
    }

    struct TokenCumulative {
        uint256 cumulativeAsk;
        uint256 cumulativeBid;
    }

    struct TokenMMInfo {
        // ask price with decimal
        uint256 askDownPrice;
        uint256 askUpPrice;
        // bid price with decimal
        uint256 bidDownPrice;
        uint256 bidUpPrice;
        uint256 askAmount;
        uint256 bidAmount;
        // k, unit is 1e18
        uint256 kAsk;
        uint256 kBid;
        // cumulative
        uint256 cumulativeAsk;
        uint256 cumulativeBid;
        // swap fee, unit is 1e18
        uint256 swapFeeRate;
        uint256 mtFeeRate;
    }

    struct RangeOrderState {
        address oracle;
        TokenMMInfo fromTokenMMInfo;
        TokenMMInfo toTokenMMInfo;
    }
}

