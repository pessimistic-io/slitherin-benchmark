// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IStorageInterfaceV5.sol";

abstract contract GNSTradingStorageV5 {
    // Constants
    uint public constant PRECISION = 1e10;
    bytes32 public constant MINTER_ROLE = 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6;
    TokenInterfaceV5 public dai;
    TokenInterfaceV5 public linkErc677;

    // Contracts (updatable)
    AggregatorInterfaceV6_2 public priceAggregator;
    PoolInterfaceV5 public pool;
    address public trading;
    address public callbacks;
    TokenInterfaceV5 public token;
    NftInterfaceV5[5] public nfts;
    IGToken public vault;

    // Trading variables
    uint public maxTradesPerPair;
    uint public maxPendingMarketOrders;
    uint public nftSuccessTimelock; // blocks
    uint[5] public spreadReductionsP; // %

    // Gov & dev addresses (updatable)
    address public gov;
    address public dev;

    // Gov & dev fees
    uint public devFeesToken; // 1e18
    uint public devFeesDai; // 1e18
    uint public govFeesToken; // 1e18
    uint public govFeesDai; // 1e18

    // Stats
    uint public tokensBurned; // 1e18
    uint public tokensMinted; // 1e18
    uint public nftRewards; // 1e18

    // Enums
    enum LimitOrder {
        TP,
        SL,
        LIQ,
        OPEN
    }

    // Structs
    struct Trade {
        address trader;
        uint pairIndex;
        uint index;
        uint initialPosToken; // 1e18
        uint positionSizeDai; // 1e18
        uint openPrice; // PRECISION
        bool buy;
        uint leverage;
        uint tp; // PRECISION
        uint sl; // PRECISION
    }
    struct TradeInfo {
        uint tokenId;
        uint tokenPriceDai; // PRECISION
        uint openInterestDai; // 1e18
        uint tpLastUpdated;
        uint slLastUpdated;
        bool beingMarketClosed;
    }
    struct OpenLimitOrder {
        address trader;
        uint pairIndex;
        uint index;
        uint positionSize; // 1e18 (DAI or GFARM2)
        uint spreadReductionP;
        bool buy;
        uint leverage;
        uint tp; // PRECISION (%)
        uint sl; // PRECISION (%)
        uint minPrice; // PRECISION
        uint maxPrice; // PRECISION
        uint block;
        uint tokenId; // index in supportedTokens
    }
    struct PendingMarketOrder {
        Trade trade;
        uint block;
        uint wantedPrice; // PRECISION
        uint slippageP; // PRECISION (%)
        uint spreadReductionP;
        uint tokenId; // index in supportedTokens
    }
    struct PendingNftOrder {
        address nftHolder;
        uint nftId;
        address trader;
        uint pairIndex;
        uint index;
        LimitOrder orderType;
    }

    // Supported tokens to open trades with
    address[] public supportedTokens;

    // Trades mappings
    mapping(address => mapping(uint => mapping(uint => Trade))) public openTrades;
    mapping(address => mapping(uint => mapping(uint => TradeInfo))) public openTradesInfo;
    mapping(address => mapping(uint => uint)) public openTradesCount;

    // Limit orders mappings
    mapping(address => mapping(uint => mapping(uint => uint))) public openLimitOrderIds;
    mapping(address => mapping(uint => uint)) public openLimitOrdersCount;
    OpenLimitOrder[] public openLimitOrders;

    // Pending orders mappings
    mapping(uint => PendingMarketOrder) public reqID_pendingMarketOrder;
    mapping(uint => PendingNftOrder) public reqID_pendingNftOrder;
    mapping(address => uint[]) public pendingOrderIds;
    mapping(address => mapping(uint => uint)) public pendingMarketOpenCount;
    mapping(address => mapping(uint => uint)) public pendingMarketCloseCount;

    // List of open trades & limit orders
    mapping(uint => address[]) public pairTraders;
    mapping(address => mapping(uint => uint)) public pairTradersId;

    // Current and max open interests for each pair
    mapping(uint => uint[3]) public openInterestDai; // 1e18 [long,short,max]

    // Restrictions & Timelocks
    mapping(uint => uint) public nftLastSuccess;

    // List of allowed contracts => can update storage + mint/burn tokens
    mapping(address => bool) public isTradingContract;

    // Events
    event SupportedTokenAdded(address a);
    event TradingContractAdded(address a);
    event TradingContractRemoved(address a);
    event AddressUpdated(string name, address a);
    event NftsUpdated(NftInterfaceV5[5] nfts);
    event NumberUpdated(string name, uint value);
    event NumberUpdatedPair(string name, uint pairIndex, uint value);
    event SpreadReductionsUpdated(uint[5]);

    function initialize(
        TokenInterfaceV5 _dai,
        TokenInterfaceV5 _linkErc677,
        TokenInterfaceV5 _token,
        NftInterfaceV5[5] memory _nfts,
        address _gov,
        address _dev,
        uint _nftSuccessTimelock
    ) external virtual;

    // Manage addresses
    function setGov(address _gov) external virtual;

    function setDev(address _dev) external virtual;

    function updateToken(TokenInterfaceV5 _newToken) external virtual;

    function updateNfts(NftInterfaceV5[5] memory _nfts) external virtual;

    // Trading + callbacks contracts
    function addTradingContract(address _trading) external virtual;

    function removeTradingContract(address _trading) external virtual;

    function addSupportedToken(address _token) external virtual;

    function setPriceAggregator(address _aggregator) external virtual;

    function setPool(address _pool) external virtual;

    function setVault(address _vault) external virtual;

    function setTrading(address _trading) external virtual;

    function setCallbacks(address _callbacks) external virtual;

    // Manage trading variables
    function setMaxTradesPerPair(uint _maxTradesPerPair) external virtual;

    function setMaxPendingMarketOrders(uint _maxPendingMarketOrders) external virtual;

    function setNftSuccessTimelock(uint _blocks) external virtual;

    function setSpreadReductionsP(uint[5] calldata _r) external virtual;

    function setMaxOpenInterestDai(uint _pairIndex, uint _newMaxOpenInterest) external virtual;

    // Manage stored trades
    function storeTrade(Trade memory _trade, TradeInfo memory _tradeInfo) external virtual;

    function unregisterTrade(address trader, uint pairIndex, uint index) external virtual;

    // Manage pending market orders
    function storePendingMarketOrder(PendingMarketOrder memory _order, uint _id, bool _open) external virtual;

    function unregisterPendingMarketOrder(uint _id, bool _open) external virtual;

    // Manage open limit orders
    function storeOpenLimitOrder(OpenLimitOrder memory o) external virtual;

    function updateOpenLimitOrder(OpenLimitOrder calldata _o) external virtual;

    function unregisterOpenLimitOrder(address _trader, uint _pairIndex, uint _index) external virtual;

    // Manage NFT orders
    function storePendingNftOrder(PendingNftOrder memory _nftOrder, uint _orderId) external virtual;

    function unregisterPendingNftOrder(uint _order) external virtual;

    // Manage open trade
    function updateSl(address _trader, uint _pairIndex, uint _index, uint _newSl) external virtual;

    function updateTp(address _trader, uint _pairIndex, uint _index, uint _newTp) external virtual;

    function updateTrade(Trade memory _t) external virtual;

    // Manage rewards
    function distributeLpRewards(uint _amount) external virtual;

    function increaseNftRewards(uint _nftId, uint _amount) external virtual;

    // Manage dev & gov fees
    function handleDevGovFees(
        uint _pairIndex,
        uint _leveragedPositionSize,
        bool _dai,
        bool _fullFee
    ) external virtual returns (uint fee);

    function claimFees() external virtual;

    // Manage tokens
    function handleTokens(address _a, uint _amount, bool _mint) external virtual;

    function transferDai(address _from, address _to, uint _amount) external virtual;

    function transferLinkToAggregator(address _from, uint _pairIndex, uint _leveragedPosDai) external virtual;

    // View utils functions
    function firstEmptyTradeIndex(address trader, uint pairIndex) public view virtual returns (uint index);

    function firstEmptyOpenLimitIndex(address trader, uint pairIndex) public view virtual returns (uint index);

    function hasOpenLimitOrder(address trader, uint pairIndex, uint index) public view virtual returns (bool);

    // Additional getters
    function pairTradersArray(uint _pairIndex) external view virtual returns (address[] memory);

    function getPendingOrderIds(address _trader) external view virtual returns (uint[] memory);

    function pendingOrderIdsCount(address _trader) external view virtual returns (uint);

    function getOpenLimitOrder(
        address _trader,
        uint _pairIndex,
        uint _index
    ) external view virtual returns (OpenLimitOrder memory);

    function getOpenLimitOrders() external view virtual returns (OpenLimitOrder[] memory);

    function getSupportedTokens() external view virtual returns (address[] memory);

    function getSpreadReductionsArray() external view virtual returns (uint[5] memory);
}

