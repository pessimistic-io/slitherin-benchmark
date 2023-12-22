// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";

import "./IGambitPriceAggregatorV1.sol";

import "./TokenInterfaceV5.sol";
import "./NftInterfaceV5.sol";
import "./PausableInterfaceV5.sol";

import "./IStableCoinDecimals.sol";

import "./GambitErrorsV1.sol";

abstract contract GambitTradingStorageV1 is IStableCoinDecimals, Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32[63] private _gap0; // storage slot gap (1 slot for Initializeable)

    // Constants
    uint public constant PRECISION = 1e10;

    // Contracts (constant)
    IERC20Upgradeable public usdc;

    bytes32[63] private _gap1; // storage slot gap (1 slot for above variable)

    // Contracts (updatable)
    IGambitPriceAggregatorV1 public priceAggregator;
    PausableInterfaceV5 public trading;
    PausableInterfaceV5 public callbacks;
    TokenInterfaceV5 public token; // FIXED: moved to constructor // NOTE: not used now
    NftInterfaceV5[5] public nfts; // FIXED: moved to constructor
    address public treasury; // NOTE: not used now
    address public vault;
    address public tokenDaiRouter;
    address public nftReward;
    address public referrals;

    bytes32[50] private _gap2; // storage slot gap (14 slots for above variables)

    // Params (adjustable)
    uint public maxTradesPerPair; // default: 3
    uint public maxTradesPerBlock; // default: 5
    uint public maxPendingMarketOrders; // default: 5
    uint public maxGainP; // default: 900; // % // DEPRECATED // TODO: remove with slot remaining
    uint public maxSlP; // default: 80; // % // DEPRECATED // TODO: remove with slot remaining
    uint public defaultLeverageUnlocked; // default: 50; // x // DEPRECATED // TODO: remove with slot remaining
    uint public nftSuccessTimelock; // default: 10; // 10 zksync batches
    uint[5] public spreadReductionsP; // default: [0, 0, 0, 0, 0]; // % // FIXED: no spread reduction // TODO: remove

    bytes32[52] private _gap3; // storage slot gap (12 slots for above variables)

    // Gov & dev & timelock addresses (updatable)
    address public timelockOwner; // TimelockController that has full control of updating any address
    address public gov; // FIXED: moved to constructor
    address public dev; // FIXED: moved to constructor

    bytes32[61] private _gap4; // storage slot gap (3 slots for above variables)

    // Gov & dev fees
    uint public devFeesToken; // 1e18 // NOTE: not used now
    uint public devFeesUsdc; // 1e6 (USDC) or 1e18 (DAI)
    uint public govFeesToken; // 1e18 // NOTE: not used now
    uint public govFeesUsdc; // 1e6 (USDC) or 1e18 (DAI)

    bytes32[60] private _gap5; // storage slot gap (4 slots for above variables)

    // Stats
    uint public tokensBurned; // 1e18 (CNG) // NOTE: not used now
    uint public tokensMinted; // 1e18 (CNG) // NOTE: not used now
    uint public nftRewards; // 1e18 (CNG) // NOTE: not used now

    bytes32[61] private _gap6; // storage slot gap (3 slots for above variables)

    // Enums
    enum LimitOrder {
        TP,
        SL,
        LIQ,
        OPEN
    }

    // Structs
    struct Trader {
        uint leverageUnlocked;
        address referral;
        uint referralRewardsTotal; // 1e18 // TODO: check it is USDC or CNG
    }

    struct Trade {
        address trader;
        uint pairIndex;
        uint index;
        uint initialPosToken; // 1e18
        uint positionSizeUsdc; // 1e6 (USDC) or 1e18 (DAI)
        uint openPrice; // PRECISION
        bool buy;
        uint leverage; // 1e18
        uint tp; // PRECISION
        uint sl; // PRECISION
    }

    struct TradeInfo {
        uint tokenId;
        uint tokenPriceUsdc; // PRECISION
        uint openInterestUsdc; // 1e6 (USDC) or 1e18 (DAI)
        uint tpLastUpdated;
        uint slLastUpdated;
        bool beingMarketClosed;
    }
    struct OpenLimitOrder {
        address trader;
        uint pairIndex;
        uint index;
        uint positionSize; // 1e6 (USDC) or 1e18 (DAI)
        uint spreadReductionP;
        bool buy;
        uint leverage; // 1e18
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

    struct PendingRemoveCollateralOrder {
        address trader;
        uint pairIndex;
        uint index;
        uint amount;
        uint openPrice;
        bool buy;
    }

    // Structs for proxy initialization
    struct ContractAddresses {
        IERC20Upgradeable usdc;
        IGambitPriceAggregatorV1 priceAggregator;
        PausableInterfaceV5 trading;
        PausableInterfaceV5 callbacks;
        address treasury;
        address vault;
        address nftReward;
        address referrals;
        address timelockOwner;
        address gov;
        address dev;
    }

    struct Parameters {
        uint maxTradesPerPair;
        uint maxTradesPerBlock;
        uint maxPendingMarketOrders;
        uint maxGainP;
        uint maxSlP;
        uint defaultLeverageUnlocked;
        uint nftSuccessTimelock;
    }

    // Supported tokens to open trades with
    address[] public supportedTokens;
    mapping(address => bool) public isSupportedToken;

    bytes32[62] private _gap7; // storage slot gap (2 slots for above variables)

    // User info mapping
    mapping(address => Trader) public traders;

    bytes32[63] private _gap8; // storage slot gap (1 slot for above variable)

    // Trades mappings
    mapping(address => mapping(uint => mapping(uint => Trade)))
        public openTrades;
    mapping(address => mapping(uint => mapping(uint => TradeInfo)))
        public openTradesInfo;
    mapping(address => mapping(uint => uint)) public openTradesCount;

    bytes32[61] private _gap9; // storage slot gap (3 slots for above variables)

    // Limit orders mappings
    mapping(address => mapping(uint => mapping(uint => uint)))
        public openLimitOrderIds;
    mapping(address => mapping(uint => uint)) public openLimitOrdersCount;
    OpenLimitOrder[] public openLimitOrders;

    bytes32[61] private _gap10; // storage slot gap (3 slots for above variables)

    // Pending orders mappings
    mapping(uint => PendingMarketOrder) public reqID_pendingMarketOrder;
    mapping(uint => PendingNftOrder) public reqID_pendingNftOrder;
    mapping(address => uint[]) public pendingOrderIds;
    mapping(address => mapping(uint => uint)) public pendingMarketOpenCount;
    mapping(address => mapping(uint => uint)) public pendingMarketCloseCount;

    mapping(uint => PendingRemoveCollateralOrder)
        public reqID_pendingRemoveCollateralOrder;
    mapping(address => mapping(uint => uint))
        public pendingRemoveCollateralOrderCount;

    bytes32[57] private _gap11; // storage slot gap (5 slots for above variables)

    // List of open trades & limit orders
    mapping(uint => address[]) public pairTraders;
    mapping(address => mapping(uint => uint)) public pairTradersId;

    bytes32[62] private _gap12; // storage slot gap (2 slots for above variables)

    // Current and max open interests for each pair (= positionSizeUsdc * leverage)
    mapping(uint => uint[3]) public openInterestUsdc; // 1e6 (USDC) or 1e18 (DAI) [long,short,max]

    bytes32[63] private _gap13; // storage slot gap (1 slot for above variable)

    // Current open position size in token for each pair (= positionSizeUsdc * leverage / openPrice)
    // Note that average open price (1e10) for each pair is `(openInterestUsdc * 1e19) / openInterestToken`
    mapping(uint => uint[2]) public openInterestToken; // 1e15 (USDC or DAI) [long,short]

    // Restrictions & Timelocks
    mapping(uint => uint) public tradesPerBlock;

    bytes32[62] private _gap14; // storage slot gap (2 slots for above variables)

    // Events
    event SupportedTokenAdded(address indexed a);
    event AddressUpdated(string name, address a);
    event NftsUpdated(NftInterfaceV5[5] nfts);
    event NumberUpdated(string name, uint value);
    event NumberUpdatedPair(string name, uint indexed pairIndex, uint value);
    event SpreadReductionsUpdated(uint[5]);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        ContractAddresses calldata _contractAddresses,
        Parameters calldata _params,
        NftInterfaceV5[5] calldata _nfts
    ) external initializer {
        if (
            address(_contractAddresses.usdc) == address(0) ||
            address(_contractAddresses.priceAggregator) == address(0) ||
            address(_contractAddresses.trading) == address(0) ||
            address(_contractAddresses.callbacks) == address(0) ||
            _contractAddresses.treasury == address(0) ||
            _contractAddresses.vault == address(0) ||
            _contractAddresses.nftReward == address(0) ||
            _contractAddresses.referrals == address(0) ||
            _contractAddresses.timelockOwner == address(0) ||
            _contractAddresses.gov == address(0) ||
            _contractAddresses.dev == address(0)
        ) revert GambitErrorsV1.ZeroAddress();

        if (
            _params.maxTradesPerPair == 0 ||
            _params.maxTradesPerBlock == 0 ||
            _params.maxPendingMarketOrders == 0 ||
            _params.maxGainP <= 300 ||
            _params.maxSlP <= 50 ||
            _params.defaultLeverageUnlocked == 0
        ) revert GambitErrorsV1.WrongParams();

        if (
            IERC20MetadataUpgradeable(address(_contractAddresses.usdc))
                .decimals() != usdcDecimals()
        ) revert GambitErrorsV1.StablecoinDecimalsMismatch();

        // load contract addresses
        usdc = _contractAddresses.usdc;
        priceAggregator = _contractAddresses.priceAggregator;
        trading = _contractAddresses.trading;
        callbacks = _contractAddresses.callbacks;
        treasury = _contractAddresses.treasury;
        vault = _contractAddresses.vault;
        nftReward = _contractAddresses.nftReward;
        referrals = _contractAddresses.referrals;
        timelockOwner = _contractAddresses.timelockOwner;
        gov = _contractAddresses.gov;
        dev = _contractAddresses.dev;

        // load params
        maxTradesPerPair = _params.maxTradesPerPair;
        maxTradesPerBlock = _params.maxTradesPerBlock;
        maxPendingMarketOrders = _params.maxPendingMarketOrders;
        maxGainP = _params.maxGainP;
        maxSlP = _params.maxSlP;
        defaultLeverageUnlocked = _params.defaultLeverageUnlocked;
        nftSuccessTimelock = _params.nftSuccessTimelock;

        nfts = _nfts;
    }

    // Modifiers
    modifier onlyGov() {
        if (msg.sender != gov) revert GambitErrorsV1.NotGov();
        _;
    }

    modifier onlyTimelockOwner() {
        if (msg.sender != timelockOwner)
            revert GambitErrorsV1.NotTimelockOwner();
        _;
    }
    modifier onlyTrading() {
        if (msg.sender != address(trading)) revert GambitErrorsV1.NotTrading();
        _;
    }
    modifier onlyCallbacks() {
        if (msg.sender != address(callbacks))
            revert GambitErrorsV1.NotCallbacks();
        _;
    }

    modifier onlyTradingOrCallbacks() {
        if (msg.sender != address(trading) && msg.sender != address(callbacks))
            revert GambitErrorsV1.NotTradingOrCallback();
        _;
    }
    modifier onlyNftRewardsOrReferralsOrCallbacks() {
        if (
            msg.sender != address(nftReward) &&
            msg.sender != address(referrals) &&
            msg.sender != address(callbacks)
        ) revert GambitErrorsV1.NotNftRewardsOrReferralsOrCallbacks();
        _;
    }

    modifier nonZeroAddress(address a) {
        if (a == address(0)) revert GambitErrorsV1.ZeroAddress();
        _;
    }

    // Manage addresses
    function setGov(address _gov) external nonZeroAddress(_gov) onlyGov {
        gov = _gov;
        emit AddressUpdated("gov", _gov);
    }

    function setDev(address _dev) external nonZeroAddress(_dev) onlyGov {
        dev = _dev;
        emit AddressUpdated("dev", _dev);
    }

    function updateTimelockOwner(
        address _timelockOwner
    ) external nonZeroAddress(_timelockOwner) onlyTimelockOwner {
        timelockOwner = _timelockOwner;
        emit AddressUpdated("timelockOwner", _timelockOwner);
    }

    function updateToken(
        TokenInterfaceV5 _newToken
    ) external nonZeroAddress(address(_newToken)) onlyTimelockOwner {
        if (!trading.isPaused() || !callbacks.isPaused())
            revert GambitErrorsV1.NotPaused();
        token = _newToken;
        emit AddressUpdated("token", address(_newToken));
    }

    function updateTreasury(
        address _treasury
    ) external nonZeroAddress(_treasury) onlyTimelockOwner {
        treasury = _treasury;
        emit AddressUpdated("treasury", _treasury);
    }

    function updateNftReward(
        address _newValue
    ) external nonZeroAddress(_newValue) onlyTimelockOwner {
        nftReward = _newValue;
        emit AddressUpdated("nftReward", nftReward);
    }

    function updateReferrals(
        address _newValue
    ) external nonZeroAddress(_newValue) onlyTimelockOwner {
        referrals = _newValue;
        emit AddressUpdated("referrals", referrals);
    }

    function updateNfts(
        NftInterfaceV5[5] memory _nfts
    ) external nonZeroAddress(address(_nfts[0])) onlyTimelockOwner {
        nfts = _nfts;
        emit NftsUpdated(_nfts);
    }

    function addSupportedToken(
        address _token
    ) external nonZeroAddress(_token) onlyTimelockOwner {
        if (isSupportedToken[_token]) revert GambitErrorsV1.AlreadyAddedToken();
        supportedTokens.push(_token);
        isSupportedToken[_token] = true;
        emit SupportedTokenAdded(_token);
    }

    function setPriceAggregator(
        address _aggregator
    ) external nonZeroAddress(_aggregator) onlyTimelockOwner {
        priceAggregator = IGambitPriceAggregatorV1(_aggregator);
        emit AddressUpdated("priceAggregator", _aggregator);
    }

    function setVault(
        address _vault
    ) external nonZeroAddress(_vault) onlyTimelockOwner {
        vault = _vault;
        emit AddressUpdated("vault", _vault);
    }

    function setTrading(
        address _trading
    ) external nonZeroAddress(_trading) onlyTimelockOwner {
        trading = PausableInterfaceV5(_trading);
        emit AddressUpdated("trading", _trading);
    }

    function setCallbacks(
        address _callbacks
    ) external nonZeroAddress(_callbacks) onlyTimelockOwner {
        callbacks = PausableInterfaceV5(_callbacks);
        emit AddressUpdated("callbacks", _callbacks);
    }

    // Manage trading variables
    function setMaxTradesPerBlock(uint _maxTradesPerBlock) external onlyGov {
        if (_maxTradesPerBlock == 0) revert GambitErrorsV1.ZeroValue();
        maxTradesPerBlock = _maxTradesPerBlock;
        emit NumberUpdated("maxTradesPerBlock", _maxTradesPerBlock);
    }

    function setMaxTradesPerPair(uint _maxTradesPerPair) external onlyGov {
        if (_maxTradesPerPair == 0) revert GambitErrorsV1.ZeroValue();
        maxTradesPerPair = _maxTradesPerPair;
        emit NumberUpdated("maxTradesPerPair", _maxTradesPerPair);
    }

    function setMaxPendingMarketOrders(
        uint _maxPendingMarketOrders
    ) external onlyGov {
        if (_maxPendingMarketOrders == 0) revert GambitErrorsV1.ZeroValue();
        maxPendingMarketOrders = _maxPendingMarketOrders;
        emit NumberUpdated("maxPendingMarketOrders", _maxPendingMarketOrders);
    }

    function setMaxGainP(uint _max) external onlyGov {
        if (_max < 300) revert GambitErrorsV1.TooLow();
        maxGainP = _max;
        emit NumberUpdated("maxGainP", _max);
    }

    function setDefaultLeverageUnlocked(uint _lev) external onlyGov {
        if (_lev == 0) revert GambitErrorsV1.ZeroValue();
        defaultLeverageUnlocked = _lev;
        emit NumberUpdated("defaultLeverageUnlocked", _lev);
    }

    function setMaxSlP(uint _max) external onlyGov {
        if (_max < 50) revert GambitErrorsV1.TooLow();
        maxSlP = _max;
        emit NumberUpdated("maxSlP", _max);
    }

    function setNftSuccessTimelock(uint _blocks) external onlyGov {
        nftSuccessTimelock = _blocks;
        emit NumberUpdated("nftSuccessTimelock", _blocks);
    }

    function setSpreadReductionsP(uint[5] calldata _r) external onlyGov {
        if (
            _r[0] == 0 ||
            _r[1] <= _r[0] ||
            _r[2] <= _r[1] ||
            _r[3] <= _r[2] ||
            _r[4] <= _r[3]
        ) revert GambitErrorsV1.WrongOrder();
        spreadReductionsP = _r;
        emit SpreadReductionsUpdated(_r);
    }

    function setMaxOpenInterestUsdc(
        uint _pairIndex,
        uint _newMaxOpenInterest
    ) external onlyGov {
        // Can set max open interest to 0 to pause trading on this pair only
        openInterestUsdc[_pairIndex][2] = _newMaxOpenInterest;
        emit NumberUpdatedPair(
            "maxOpenInterestUsdc",
            _pairIndex,
            _newMaxOpenInterest
        );
    }

    // Manage stored trades

    // 콜백에서 호출
    //  - openTradeMarketCallback
    //  - executeNftOpenOrderCallback
    function storeTrade(
        Trade memory _trade,
        TradeInfo memory _tradeInfo
    ) external onlyCallbacks {
        _trade.index = firstEmptyTradeIndex(_trade.trader, _trade.pairIndex);
        openTrades[_trade.trader][_trade.pairIndex][_trade.index] = _trade;

        openTradesCount[_trade.trader][_trade.pairIndex] += 1;
        tradesPerBlock[block.number] += 1;

        if (openTradesCount[_trade.trader][_trade.pairIndex] == 1) {
            pairTradersId[_trade.trader][_trade.pairIndex] = pairTraders[
                _trade.pairIndex
            ].length;
            pairTraders[_trade.pairIndex].push(_trade.trader);
        }

        _tradeInfo.beingMarketClosed = false;
        openTradesInfo[_trade.trader][_trade.pairIndex][
            _trade.index
        ] = _tradeInfo;

        updateOpenInterestUsdc(
            _trade.pairIndex,
            _trade.openPrice,
            _tradeInfo.openInterestUsdc,
            true,
            _trade.buy
        );
    }

    function unregisterTrade(
        address trader,
        uint pairIndex,
        uint index
    ) external onlyCallbacks {
        Trade storage t = openTrades[trader][pairIndex][index];
        TradeInfo storage i = openTradesInfo[trader][pairIndex][index];
        if (t.leverage == 0) {
            return;
        }

        updateOpenInterestUsdc(
            pairIndex,
            t.openPrice,
            i.openInterestUsdc,
            false,
            t.buy
        );

        if (openTradesCount[trader][pairIndex] == 1) {
            uint _pairTradersId = pairTradersId[trader][pairIndex];
            address[] storage p = pairTraders[pairIndex];

            p[_pairTradersId] = p[p.length - 1];
            pairTradersId[p[_pairTradersId]][pairIndex] = _pairTradersId;

            delete pairTradersId[trader][pairIndex];
            p.pop();
        }

        delete openTrades[trader][pairIndex][index];
        delete openTradesInfo[trader][pairIndex][index];

        openTradesCount[trader][pairIndex] -= 1;
        tradesPerBlock[block.number] += 1;
    }

    // Manage pending market orders
    function storePendingMarketOrder(
        PendingMarketOrder memory _order,
        uint _id,
        bool _open
    ) external onlyTrading {
        pendingOrderIds[_order.trade.trader].push(_id);

        reqID_pendingMarketOrder[_id] = _order;
        reqID_pendingMarketOrder[_id].block = block.number;

        if (_open) {
            pendingMarketOpenCount[_order.trade.trader][
                _order.trade.pairIndex
            ] += 1;
        } else {
            pendingMarketCloseCount[_order.trade.trader][
                _order.trade.pairIndex
            ] += 1;
            openTradesInfo[_order.trade.trader][_order.trade.pairIndex][
                _order.trade.index
            ].beingMarketClosed = true;
        }
    }

    function unregisterPendingMarketOrder(
        uint _id,
        bool _open
    ) external onlyTradingOrCallbacks {
        PendingMarketOrder memory _order = reqID_pendingMarketOrder[_id];
        uint[] storage orderIds = pendingOrderIds[_order.trade.trader];

        for (uint i = 0; i < orderIds.length; i++) {
            if (orderIds[i] == _id) {
                if (_open) {
                    pendingMarketOpenCount[_order.trade.trader][
                        _order.trade.pairIndex
                    ] -= 1;
                } else {
                    pendingMarketCloseCount[_order.trade.trader][
                        _order.trade.pairIndex
                    ] -= 1;
                    openTradesInfo[_order.trade.trader][_order.trade.pairIndex][
                        _order.trade.index
                    ].beingMarketClosed = false;
                }

                orderIds[i] = orderIds[orderIds.length - 1];
                orderIds.pop();

                delete reqID_pendingMarketOrder[_id];
                return;
            }
        }
    }

    // Manage open interest
    function updateOpenInterestUsdc(
        uint _pairIndex,
        uint _openPrice, // 1e10
        uint _leveragedPosUsdc, // 1e6 (USDC) or 1e18 (DAI)
        bool _open,
        bool _long
    ) private {
        uint index = _long ? 0 : 1;
        uint[3] storage o = openInterestUsdc[_pairIndex];
        uint[2] storage pt = openInterestToken[_pairIndex]; // 1e15 (USDC or DAI)

        // 1e6 (USDC) or 1e18 (DAI)
        o[index] = _open
            ? o[index] + _leveragedPosUsdc
            : o[index] - _leveragedPosUsdc;

        // 1e19 (USDC) or 1e7 (DAI)
        uint d = 10 ** (25 - usdcDecimals());

        // USDC: 1e15 = 1e6  * "1e19" / 1e10
        // DAI:  1e15 = 1e18 * "1e7"  / 1e10
        pt[index] = _open
            ? pt[index] + (_leveragedPosUsdc * d) / _openPrice
            : pt[index] - (_leveragedPosUsdc * d) / _openPrice;
    }

    // Manage open limit orders
    function storeOpenLimitOrder(OpenLimitOrder memory o) external onlyTrading {
        o.index = firstEmptyOpenLimitIndex(o.trader, o.pairIndex);
        o.block = block.number;
        openLimitOrders.push(o);
        openLimitOrderIds[o.trader][o.pairIndex][o.index] =
            openLimitOrders.length -
            1;
        openLimitOrdersCount[o.trader][o.pairIndex] += 1;
    }

    function updateOpenLimitOrder(
        OpenLimitOrder calldata _o
    ) external onlyTrading {
        if (!hasOpenLimitOrder(_o.trader, _o.pairIndex, _o.index)) {
            return;
        }
        OpenLimitOrder storage o = openLimitOrders[
            openLimitOrderIds[_o.trader][_o.pairIndex][_o.index]
        ];
        o.positionSize = _o.positionSize;
        o.buy = _o.buy;
        o.leverage = _o.leverage;
        o.tp = _o.tp;
        o.sl = _o.sl;
        o.minPrice = _o.minPrice;
        o.maxPrice = _o.maxPrice;
        o.block = block.number;
    }

    function unregisterOpenLimitOrder(
        address _trader,
        uint _pairIndex,
        uint _index
    ) external onlyTradingOrCallbacks {
        if (!hasOpenLimitOrder(_trader, _pairIndex, _index)) {
            return;
        }

        // Copy last order to deleted order => update id of this limit order
        uint id = openLimitOrderIds[_trader][_pairIndex][_index];
        openLimitOrders[id] = openLimitOrders[openLimitOrders.length - 1];
        openLimitOrderIds[openLimitOrders[id].trader][
            openLimitOrders[id].pairIndex
        ][openLimitOrders[id].index] = id;

        // Remove
        delete openLimitOrderIds[_trader][_pairIndex][_index];
        openLimitOrders.pop();

        openLimitOrdersCount[_trader][_pairIndex] -= 1;
    }

    // Manage NFT orders
    function storePendingNftOrder(
        PendingNftOrder memory _nftOrder,
        uint _orderId
    ) external onlyTrading {
        reqID_pendingNftOrder[_orderId] = _nftOrder;
    }

    function unregisterPendingNftOrder(uint _order) external onlyCallbacks {
        delete reqID_pendingNftOrder[_order];
    }

    // Manage RemoveCollateral orders
    function storePendingRemoveCollateralOrder(
        PendingRemoveCollateralOrder memory _removeCollateralOrder,
        uint _orderId
    ) external onlyTrading {
        pendingOrderIds[_removeCollateralOrder.trader].push(_orderId);
        reqID_pendingRemoveCollateralOrder[_orderId] = _removeCollateralOrder;
    }

    function unregisterPendingRemoveCollateralOrder(
        uint _orderId
    ) external onlyCallbacks {
        PendingRemoveCollateralOrder
            memory order = reqID_pendingRemoveCollateralOrder[_orderId];
        uint[] storage orderIds = pendingOrderIds[order.trader];
        uint len = orderIds.length;
        for (uint i = 0; i < len; i++) {
            if (orderIds[i] == _orderId) {
                orderIds[i] = orderIds[len - 1];
                orderIds.pop();
                break;
            }
        }
        delete reqID_pendingRemoveCollateralOrder[_orderId];
    }

    // Manage open trade
    function updateSl(
        address _trader,
        uint _pairIndex,
        uint _index,
        uint _newSl
    ) external onlyTradingOrCallbacks {
        Trade storage t = openTrades[_trader][_pairIndex][_index];
        TradeInfo storage i = openTradesInfo[_trader][_pairIndex][_index];
        if (t.leverage == 0) {
            return;
        }
        t.sl = _newSl;
        i.slLastUpdated = block.number;
    }

    function updateTp(
        address _trader,
        uint _pairIndex,
        uint _index,
        uint _newTp
    ) external onlyTrading {
        Trade storage t = openTrades[_trader][_pairIndex][_index];
        TradeInfo storage i = openTradesInfo[_trader][_pairIndex][_index];
        if (t.leverage == 0) {
            return;
        }
        t.tp = _newTp;
        i.tpLastUpdated = block.number;
    }

    function updateTrade(Trade memory _t) external onlyTradingOrCallbacks {
        // useful when partial adding/closing
        Trade storage t = openTrades[_t.trader][_t.pairIndex][_t.index];
        if (t.leverage == 0) {
            return;
        }
        t.initialPosToken = _t.initialPosToken;
        t.positionSizeUsdc = _t.positionSizeUsdc;
        t.openPrice = _t.openPrice;
        t.leverage = _t.leverage;
    }

    // Manage referrals
    function storeReferral(
        address _trader,
        address _referral
    ) external onlyTrading {
        Trader storage trader = traders[_trader];
        trader.referral = _referral != address(0) &&
            trader.referral == address(0) &&
            _referral != _trader
            ? _referral
            : trader.referral;
    }

    function increaseReferralRewards(
        address _referral,
        uint _amount
    ) external onlyTrading {
        traders[_referral].referralRewardsTotal += _amount;
    }

    // Unlock next leverage
    function setLeverageUnlocked(
        address _trader,
        uint _newLeverage
    ) external onlyTrading {
        traders[_trader].leverageUnlocked = _newLeverage;
    }

    // Manage dev & gov fees
    function handleDevGovFees(
        uint _pairIndex,
        uint _leveragedPositionSize, // 1e6 (USDC) or 1e18 (DAI)
        bool _fullFee // if false, charge a quater of the fee
    )
        external
        onlyCallbacks
        returns (
            uint fee // 1e6 (USDC) or 1e18 (DAI)
        )
    {
        fee = getDevGovFees(_pairIndex, _leveragedPositionSize, _fullFee) / 2;

        govFeesUsdc += fee;
        devFeesUsdc += fee;

        fee = fee * 2;
    }

    function handleGovFee(uint _fee) external onlyCallbacks {
        govFeesUsdc += _fee;
    }

    function getDevGovFees(
        uint _pairIndex,
        uint _leveragedPositionSize, // 1e6 (USDC) or 1e18 (DAI)
        bool _fullFee // if false, charge a quater of the fee ((dev fee + gov fee) / 4)
    )
        public
        view
        returns (
            uint fee // 1e6 (USDC) or 1e18 (DAI), dev fee + gov fee
        )
    {
        fee =
            (_leveragedPositionSize * priceAggregator.openFeeP(_pairIndex)) /
            PRECISION /
            100;
        if (!_fullFee) {
            fee /= 4;
        }

        fee = fee * 2;
    }

    function claimFees() external onlyGov {
        usdc.safeTransfer(gov, govFeesUsdc);
        usdc.safeTransfer(dev, devFeesUsdc);

        devFeesUsdc = 0;
        govFeesUsdc = 0;
    }

    // Manage tokens
    // TODO: after CNG integration, use treasury as an alternative source of CNG (mint/burn)
    function handleTokens(
        address _a,
        uint _amount,
        bool _mint
    ) external onlyNftRewardsOrReferralsOrCallbacks {
        // skip if token is not set yet.
        if (address(token) == address(0)) return;

        if (_mint) {
            tokensMinted += _amount;
            token.mint(_a, _amount);
        } else {
            tokensBurned += _amount;
            token.burn(_a, _amount);
        }
    }

    function transferUsdc(
        address _from,
        address _to,
        uint _amount
    ) external onlyTradingOrCallbacks {
        if (_from == address(this)) {
            usdc.safeTransfer(_to, _amount);
        } else {
            usdc.safeTransferFrom(_from, _to, _amount);
        }
    }

    // View utils functions
    function firstEmptyTradeIndex(
        address trader,
        uint pairIndex
    ) public view returns (uint index) {
        for (uint i = 0; i < maxTradesPerPair; i++) {
            if (openTrades[trader][pairIndex][i].leverage == 0) {
                index = i;
                break;
            }
        }
    }

    function firstEmptyOpenLimitIndex(
        address trader,
        uint pairIndex
    ) public view returns (uint index) {
        for (uint i = 0; i < maxTradesPerPair; i++) {
            if (!hasOpenLimitOrder(trader, pairIndex, i)) {
                index = i;
                break;
            }
        }
    }

    function hasOpenLimitOrder(
        address trader,
        uint pairIndex,
        uint index
    ) public view returns (bool) {
        if (openLimitOrders.length == 0) {
            return false;
        }
        OpenLimitOrder storage o = openLimitOrders[
            openLimitOrderIds[trader][pairIndex][index]
        ];
        return
            o.trader == trader && o.pairIndex == pairIndex && o.index == index;
    }

    // Additional getters
    function getReferral(address _trader) external view returns (address) {
        return traders[_trader].referral;
    }

    function getLeverageUnlocked(address _trader) external view returns (uint) {
        return traders[_trader].leverageUnlocked;
    }

    function pairTradersArray(
        uint _pairIndex
    ) external view returns (address[] memory) {
        return pairTraders[_pairIndex];
    }

    function getPendingOrderIds(
        address _trader
    ) external view returns (uint[] memory) {
        return pendingOrderIds[_trader];
    }

    function pendingOrderIdsCount(
        address _trader
    ) external view returns (uint) {
        return pendingOrderIds[_trader].length;
    }

    function getOpenLimitOrder(
        address _trader,
        uint _pairIndex,
        uint _index
    ) external view returns (OpenLimitOrder memory) {
        if (!hasOpenLimitOrder(_trader, _pairIndex, _index))
            revert GambitErrorsV1.NotOpenLimitOrder();
        return openLimitOrders[openLimitOrderIds[_trader][_pairIndex][_index]];
    }

    function getOpenLimitOrders()
        external
        view
        returns (OpenLimitOrder[] memory)
    {
        return openLimitOrders;
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    function getSpreadReductionsArray() external view returns (uint[5] memory) {
        return spreadReductionsP;
    }

    function usdcDecimals() public pure virtual returns (uint8);
}

/**
 * @dev GambitTradingStorageV1 with stablecoin decimals set to 6.
 */
contract GambitTradingStorageV1____6 is GambitTradingStorageV1 {
    function usdcDecimals() public pure override returns (uint8) {
        return 6;
    }
}

/**
 * @dev GambitTradingStorageV1 with stablecoin decimals set to 18.
 */
contract GambitTradingStorageV1____18 is GambitTradingStorageV1 {
    function usdcDecimals() public pure override returns (uint8) {
        return 18;
    }
}

