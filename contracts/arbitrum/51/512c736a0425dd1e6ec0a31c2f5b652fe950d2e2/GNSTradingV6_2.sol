// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./GNSPairInfosV6_1.sol";
import "./IStorageInterfaceV5.sol";
import "./GNSNftRewardsV6.sol";
import "./GNSReferralsInterfaceV6_2.sol";

abstract contract GNSTradingV6_2 {
    // Contracts (constant)
    StorageInterfaceV5 public immutable storageT;
    GNSNftRewardsV6 public immutable nftRewards;
    GNSPairInfosV6_1 public immutable pairInfos;
    GNSReferralsInterfaceV6_2 public immutable referrals;

    // Params (constant)
    uint constant PRECISION = 1e10;
    uint constant MAX_SL_P = 75; // -75% PNL

    // Params (adjustable)
    uint public maxPosDai; // 1e18 (eg. 75000 * 1e18)
    uint public limitOrdersTimelock; // block (eg. 30)
    uint public marketOrdersTimeout; // block (eg. 30)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    // Events
    event Done(bool done);
    event Paused(bool paused);

    event NumberUpdated(string name, uint value);

    event MarketOrderInitiated(uint indexed orderId, address indexed trader, uint indexed pairIndex, bool open);

    event OpenLimitPlaced(address indexed trader, uint indexed pairIndex, uint index);
    event OpenLimitUpdated(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newPrice,
        uint newTp,
        uint newSl
    );
    event OpenLimitCanceled(address indexed trader, uint indexed pairIndex, uint index);

    event TpUpdated(address indexed trader, uint indexed pairIndex, uint index, uint newTp);
    event SlUpdated(address indexed trader, uint indexed pairIndex, uint index, uint newSl);
    event SlUpdateInitiated(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newSl
    );

    event NftOrderInitiated(uint orderId, address indexed nftHolder, address indexed trader, uint indexed pairIndex);
    event NftOrderSameBlock(address indexed nftHolder, address indexed trader, uint indexed pairIndex);

    event ChainlinkCallbackTimeout(uint indexed orderId, StorageInterfaceV5.PendingMarketOrder order);
    event CouldNotCloseTrade(address indexed trader, uint indexed pairIndex, uint index);

    constructor(
        StorageInterfaceV5 _storageT,
        GNSNftRewardsV6 _nftRewards,
        GNSPairInfosV6_1 _pairInfos,
        GNSReferralsInterfaceV6_2 _referrals,
        uint _maxPosDai,
        uint _limitOrdersTimelock,
        uint _marketOrdersTimeout
    ) {
        require(
            address(_storageT) != address(0) &&
                address(_nftRewards) != address(0) &&
                address(_pairInfos) != address(0) &&
                address(_referrals) != address(0) &&
                _maxPosDai > 0 &&
                _limitOrdersTimelock > 0 &&
                _marketOrdersTimeout > 0,
            "WRONG_PARAMS"
        );

        storageT = _storageT;
        nftRewards = _nftRewards;
        pairInfos = _pairInfos;
        referrals = _referrals;

        maxPosDai = _maxPosDai;
        limitOrdersTimelock = _limitOrdersTimelock;
        marketOrdersTimeout = _marketOrdersTimeout;
    }

    // Manage params
    function setMaxPosDai(uint value) external virtual;

    function setLimitOrdersTimelock(uint value) external virtual;

    function setMarketOrdersTimeout(uint value) external virtual;

    // Manage state
    function pause() external virtual;

    function done() external virtual;

    // Open new trade (MARKET/LIMIT)
    function openTrade(
        StorageInterfaceV5.Trade memory t,
        GNSNftRewardsV6.OpenLimitOrderType orderType, // LEGACY => market
        uint spreadReductionId,
        uint slippageP, // for market orders only
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
        uint sl
    ) external virtual;

    function cancelOpenLimitOrder(uint pairIndex, uint index) external virtual;

    // Manage limit order (TP/SL)
    function updateTp(uint pairIndex, uint index, uint newTp) external virtual;

    function updateSl(uint pairIndex, uint index, uint newSl) external virtual;

    // Execute limit order
    function executeNftOrder(
        StorageInterfaceV5.LimitOrder orderType,
        address trader,
        uint pairIndex,
        uint index,
        uint nftId,
        uint nftType
    ) external virtual;

    // Market timeout
    function openTradeMarketTimeout(uint _order) external virtual;

    function closeTradeMarketTimeout(uint _order) external virtual;
}

