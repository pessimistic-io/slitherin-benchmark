// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

enum OrderType {
    None, // 0
    PositionOrder, // 1
    LiquidityOrder, // 2
    WithdrawalOrder, // 3
    RebalanceOrder, // 4
    FlashTakePositionOrder // 5
}

//                                  160        152       144         120        96   72   64               8        0
// +----------------------------------------------------------------------------------+--------------------+--------+
// |              subAccountId 184 (already shifted by 72bits)                        |     orderId 64     | type 8 |
// +----------------------------------+----------+---------+-----------+---------+---------+---------------+--------+
// |              size 96             | profit 8 | flags 8 | unused 24 | exp 24  | time 32 |      enumIndex 64      |
// +----------------------------------+----------+---------+-----------+---------+---------+---------------+--------+
// |             price 96             |                    collateral 96                   |        unused 64       |
// +----------------------------------+----------------------------------------------------+------------------------+
struct PositionOrder {
    uint64 id;
    bytes32 subAccountId; // 160 + 8 + 8 + 8 = 184
    uint96 collateral; // erc20.decimals
    uint96 size; // 1e18
    uint96 price; // 1e18
    uint8 profitTokenId;
    uint8 flags; // see LibOrder.POSITION_*
    uint32 placeOrderTime; // 1e0
    uint24 expire10s; // 10 seconds. deadline = placeOrderTime + expire * 10
}

//                                  160       152       144          96          72    64              8        0
// +------------------------------------------------------------------+-----------+--------------------+--------+
// |                        account 160                               | unused 24 |     orderId 64     | type 8 |
// +----------------------------------+---------+---------+-----------+-----------+-----+--------------+--------+
// |             amount 96            | asset 8 | flags 8 | unused 48 |     time 32     |      enumIndex 64     |
// +----------------------------------+---------+---------+-----------+-----------------+-----------------------+
// |                                                 unused 256                                                 |
// +------------------------------------------------------------------------------------------------------------+
struct LiquidityOrder {
    uint64 id;
    address account;
    uint96 rawAmount; // erc20.decimals
    uint8 assetId;
    bool isAdding;
    uint32 placeOrderTime; // 1e0
}

//                                  160        152       144          96   72       64               8        0
// +------------------------------------------------------------------------+------------------------+--------+
// |              subAccountId 184 (already shifted by 72bits)              |       orderId 64       | type 8 |
// +----------------------------------+----------+---------+-----------+----+--------+---------------+--------+
// |             amount 96            | profit 8 | flags 8 | unused 48 |   time 32   |      enumIndex 64      |
// +----------------------------------+----------+---------+-----------+-------------+------------------------+
// |                                                unused 256                                                |
// +----------------------------------------------------------------------------------------------------------+
struct WithdrawalOrder {
    uint64 id;
    bytes32 subAccountId; // 160 + 8 + 8 + 8 = 184
    uint96 rawAmount; // erc20.decimals
    uint8 profitTokenId;
    bool isProfit;
    uint32 placeOrderTime; // 1e0
}

//                                          160       96      88      80        72    64                 8        0
// +---------------------------------------------------+-------+-------+----------+----------------------+--------+
// |                  rebalancer 160                   | id0 8 | id1 8 | unused 8 |      orderId 64      | type 8 |
// +------------------------------------------+--------+-------+-------+----------+----+-----------------+--------+
// |                amount0 96                |                amount1 96              |       enumIndex 64       |
// +------------------------------------------+----------------------------------------+--------------------------+
// |                                                 userData 256                                                 |
// +--------------------------------------------------------------------------------------------------------------+
struct RebalanceOrder {
    uint64 id;
    address rebalancer;
    uint8 tokenId0;
    uint8 tokenId1;
    uint96 rawAmount0; // erc20.decimals
    uint96 maxRawAmount1; // erc20.decimals
    bytes32 userData;
}

struct FlashTakeParam {
    FlashTakeEIP712 order;
    uint64 flashTakeSequence;
    bytes signature;
    uint96 assetPrice; // 1e18
    uint96 collateralPrice; // 1e18
    uint96 profitAssetPrice; // 1e18
}

/**
 * @notice Open/close position. Assembled by Trader.
 *
 *         Market order will expire after marketOrderTimeout seconds.
 * @param  subAccountId       sub account id. see LibSubAccount.decodeSubAccountId.
 * @param  collateral         deposit collateral before open; or withdraw collateral after close. decimals = erc20.decimals.
 * @param  size               position size. decimals = 18.
 * @param  gasFee             transfer broker fee from collateral. decimals = 18.
 * @param  profitTokenId      specify the profitable asset.id when closing a position and making a profit.
 *                            take no effect when opening a position or loss.
 * @param  flags              a bitset of LibOrder.POSITION_*
 *                            POSITION_INCREASING               0x80 means openPosition; otherwise closePosition
 *                            POSITION_MARKET_ORDER             0x40 means ignore limitPrice
 *                            POSITION_WITHDRAW_ALL_IF_EMPTY    0x20 means auto withdraw all collateral if position.size == 0
 *                            POSITION_TRIGGER_ORDER            0x10 means this is a trigger order (ex: stop-loss order). 0 means this is a limit order (ex: take-profit order)
 * @param  referralCode       set referral code of the trading account.
 * @param  placeOrderTime     a UNIX timestamp. Market order will expire after marketOrderTimeout seconds.
 * @param  salt               a random value that keeps EIP712 message hash different.
 * @param  orderType          should be FlashTakePositionOrder
 */
struct FlashTakeEIP712 {
    bytes32 subAccountId;
    uint96 collateral; // erc20.decimals
    uint96 size; // 1e18
    uint96 gasFee; // 1e18
    bytes32 referralCode;
    uint8 orderType;
    uint8 flags;
    uint8 profitTokenId;
    uint32 placeOrderTime;
    uint32 salt;
}

