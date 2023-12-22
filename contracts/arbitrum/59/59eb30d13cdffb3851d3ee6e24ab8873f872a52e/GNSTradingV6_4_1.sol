// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IStorageInterfaceV5.sol";
import "./GNSReferralsInterfaceV6_2.sol";
import "./IGNSOracleRewardsV6_4_1.sol";
import "./GNSBorrowingFeesInterfaceV6_4.sol";
import "./GNSPairInfosV6_1.sol";
import "./GNSNftRewardsV6.sol";

abstract contract GNSTradingV6_4_1 {
    // Contracts (constant)
    StorageInterfaceV5 public storageT;
    IGNSOracleRewardsV6_4_1 public oracleRewards;
    GNSPairInfosV6_1 public pairInfos;
    GNSReferralsInterfaceV6_2 public referrals;
    GNSBorrowingFeesInterfaceV6_4 public borrowingFees;

    // Params (constant)
    uint private constant PRECISION = 1e10;
    uint private constant MAX_SL_P = 75; // -75% PNL

    // Params (adjustable)
    uint public maxPosDai; // 1e18 (eg. 75000 * 1e18)
    uint public marketOrdersTimeout; // block (eg. 30)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    mapping(address => bool) public bypassTriggerLink; // Doesn't have to pay link in executeNftOrder()

    // Events
    event Done(bool done);
    event Paused(bool paused);

    event NumberUpdated(string name, uint value);
    event BypassTriggerLinkUpdated(address user, bool bypass);

    event MarketOrderInitiated(uint indexed orderId, address indexed trader, uint indexed pairIndex, bool open);

    event OpenLimitPlaced(address indexed trader, uint indexed pairIndex, uint index);
    event OpenLimitUpdated(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newPrice,
        uint newTp,
        uint newSl,
        uint maxSlippageP
    );
    event OpenLimitCanceled(address indexed trader, uint indexed pairIndex, uint index);

    event TpUpdated(address indexed trader, uint indexed pairIndex, uint index, uint newTp);
    event SlUpdated(address indexed trader, uint indexed pairIndex, uint index, uint newSl);

    event NftOrderInitiated(uint orderId, address indexed trader, uint indexed pairIndex, bool byPassesLinkCost);

    event ChainlinkCallbackTimeout(uint indexed orderId, StorageInterfaceV5.PendingMarketOrder order);
    event CouldNotCloseTrade(address indexed trader, uint indexed pairIndex, uint index);

    // Manage params
    
    // Manage state

    // Open new trade (MARKET/LIMIT)
    function openTrade(
        StorageInterfaceV5.Trade memory t,
        IGNSOracleRewardsV6_4_1.OpenLimitOrderType orderType, // LEGACY => market
        uint slippageP, // 1e10 (%)
        address referrer
    ) external virtual;

    // Close trade (MARKET)
    function closeTradeMarket(uint pairIndex, uint index) external virtual;
    
    // Manage limit order (OPEN)
    function updateOpenLimitOrder(
        uint pairIndex,
        uint index,
        uint price, // PRECISION
        uint tp,
        uint sl,
        uint maxSlippageP
    ) external virtual;

    function cancelOpenLimitOrder(uint pairIndex, uint index) external virtual;

    // Manage limit order (TP/SL)
    function updateTp(uint pairIndex, uint index, uint newTp) external virtual;

    function updateSl(uint pairIndex, uint index, uint newSl) external virtual;

    // Execute limit order
    function executeNftOrder(uint256 packed) external virtual;

    // Market timeout
    function openTradeMarketTimeout(uint _order) external virtual;

    function closeTradeMarketTimeout(uint _order) external virtual;
}

