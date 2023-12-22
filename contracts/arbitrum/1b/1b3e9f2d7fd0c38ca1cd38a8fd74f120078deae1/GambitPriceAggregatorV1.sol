// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";

import "./IUniswapV3Pool.sol";
import "./IPyth.sol";
import "./PythStructs.sol";

import "./Multicall.sol";
import "./IGambitTradingCallbacksV1.sol";
import "./ITWAPPriceGetter.sol";
import "./ChainlinkFeedInterfaceV5.sol";
import "./IGambitTradingStorageV1.sol";
import "./IGambitCNGCollateral.sol";

import "./GambitErrorsV1.sol";

contract GambitPriceAggregatorV1 is Initializable, ITWAPPriceGetter, Multicall {
    bytes32[63] private _gap0; // storage slot gap (1 slot for Initializeable)

    // Contracts (constant)
    IGambitTradingStorageV1 public storageT;

    // Contracts (adjustable)
    IGambitPairsStorageV1 public pairsStorage;
    IPyth public pyth;
    ITWAPPriceGetter public twapPriceGetter;
    IGambitCNGCollateral public cngCol;

    bytes32[59] private _gap1; // storage slot gap (4 slots for above variables)

    // Params (constant)
    uint constant PRECISION = 1e10;

    // Params (adjustable)
    uint public PYTH_PRICE_AGE;

    bytes32[63] private _gap2; // storage slot gap (1 slot for above variable)

    // Custom data types
    enum OrderType {
        MARKET_OPEN,
        MARKET_CLOSE,
        LIMIT_OPEN,
        LIMIT_CLOSE,
        UPDATE_SL,
        REMOVE_COLLATERAL
    }

    struct Order {
        uint pairIndex;
        OrderType orderType;
        bool initiated;
    }

    struct PendingSl {
        address trader;
        uint pairIndex;
        uint index;
        uint openPrice;
        bool buy;
        uint newSl;
    }

    // State
    mapping(uint => Order) public orders;
    mapping(uint => PendingSl) public pendingSlOrders;

    bytes32[62] private _gap3; // storage slot gap (2 slots for above variables)

    bool public enableChainlinkFeed;

    bytes32[63] private _gap4; // storage slot gap (1 slot for above variable)

    // Events
    event PairsStorageUpdated(address indexed value);
    event PythUpdated(address indexed value);
    event EnableChainlinkFeedUpdated(bool value);
    event TwapPriceGetterUpdated(address indexed value);
    event PythPriceAgeUpdated(uint value);

    event PriceRequested(
        uint indexed orderId,
        uint indexed pairIndex,
        OrderType orderType
    );

    event PriceReceived(
        uint indexed orderId,
        address indexed node,
        uint indexed pairIndex,
        uint price,
        uint referencePrice
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IGambitTradingStorageV1 _storageT,
        IGambitPairsStorageV1 _pairsStorage,
        IPyth _pyth,
        ITWAPPriceGetter _twapPriceGetter,
        IGambitCNGCollateral _cngCol
    ) external initializer {
        if (
            address(_storageT) == address(0) ||
            address(_pairsStorage) == address(0) ||
            address(_pyth) == address(0) ||
            address(_twapPriceGetter) == address(0) ||
            address(_cngCol) == address(0)
        ) revert GambitErrorsV1.WrongParams();

        storageT = _storageT;
        pyth = _pyth;
        twapPriceGetter = _twapPriceGetter;
        cngCol = _cngCol;

        pairsStorage = _pairsStorage;
        PYTH_PRICE_AGE = 3 minutes; // TODO: reduce to 1 min when zksync supports L2 timestamp
    }

    // Modifiers
    modifier onlyGov() {
        if (msg.sender != storageT.gov()) revert GambitErrorsV1.NotGov();
        _;
    }
    modifier onlyTrading() {
        if (msg.sender != storageT.trading())
            revert GambitErrorsV1.NotTrading();
        _;
    }

    // Manage contracts
    function updatePairsStorage(IGambitPairsStorageV1 value) external onlyGov {
        if (address(value) == address(0)) revert GambitErrorsV1.ZeroAddress();

        pairsStorage = value;

        emit PairsStorageUpdated(address(value));
    }

    function updatePyth(IPyth value) external onlyGov {
        if (address(value) == address(0)) revert GambitErrorsV1.ZeroAddress();

        pyth = value;

        emit PythUpdated(address(value));
    }

    // we only set cngCol if empty (during upgrade)
    function setCngCol(IGambitCNGCollateral value) external onlyGov {
        if (address(value) == address(0)) revert GambitErrorsV1.ZeroAddress();
        if (address(cngCol) != address(0)) revert GambitErrorsV1.WrongParams();

        cngCol = value;
    }

    function updateTwapPriceGetter(ITWAPPriceGetter value) external onlyGov {
        if (address(value) == address(0)) revert GambitErrorsV1.ZeroAddress();

        twapPriceGetter = value;

        emit TwapPriceGetterUpdated(address(value));
    }

    function updateEnableChainlinkFeed(bool value) external onlyGov {
        enableChainlinkFeed = value;
        emit EnableChainlinkFeedUpdated(value);
    }

    function updatePythPriceAge(uint value) external onlyGov {
        if (value == 0) revert GambitErrorsV1.ZeroValue();
        PYTH_PRICE_AGE = value;
        emit PythPriceAgeUpdated(value);
    }

    // ITWAPPriceGetter functions
    function token() external view returns (address) {
        return twapPriceGetter.token();
    }

    function uniV3Pool() external view returns (IUniswapV3Pool) {
        return twapPriceGetter.uniV3Pool();
    }

    function twapInterval() external view returns (uint32) {
        return twapPriceGetter.twapInterval();
    }

    function isGnsToken0InLp() external view returns (bool) {
        return twapPriceGetter.isGnsToken0InLp();
    }

    function tokenPriceUsdc() external view returns (uint price) {
        return twapPriceGetter.tokenPriceUsdc();
    }

    // On-demand price request to oracles network
    function getPrice(
        uint pairIndex,
        OrderType orderType,
        uint leveragedPosUsdc // 1e6 (USDC) or 1e18 (DAI)
    ) external onlyTrading returns (uint) {
        (, , uint orderId) = pairsStorage.pairJob(pairIndex);

        orders[orderId] = Order({
            pairIndex: pairIndex,
            orderType: orderType,
            initiated: true
        });
        emit PriceRequested(orderId, pairIndex, orderType);

        return orderId;
    }

    // Fulfill optimistic on-demand price requests
    function fulfill(
        uint orderId,
        PythStructs.Price calldata pythPrice
    ) external payable returns (uint256 price, uint256 conf, bool success) {
        if (
            // NFT#1 holder - for market order settlement
            storageT.nfts(0).balanceOf(msg.sender) == 0 &&
            // trading contract - for nft order execution
            msg.sender != storageT.trading()
        ) revert GambitErrorsV1.NoAuth();

        Order memory r = orders[orderId];

        uint256 feedPrice;
        uint256 feedMaxDeviationP;
        (feedMaxDeviationP, feedPrice, price, conf) = updatePrice(
            orderId,
            pythPrice
        );

        if (
            feedMaxDeviationP == 0 && feedPrice == 0 && price == 0 && conf == 0
        ) {
            return (0, 0, false);
        }

        IGambitPairsStorageV1.Feed memory f = pairsStorage.pairFeed(
            r.pairIndex
        );

        if (
            // price could be zero if pyth network is not working
            price == 0 || // NOTE: allow price to be zero to support order canceling (or allow trading for only pairs that both of chainlink and pyth network work)
            // chalinlink feed checking could be disabled. in this case, skip below chcecking
            !enableChainlinkFeed ||
            f.feed1 == address(0) ||
            // check pyth network price is in acceptable range of chainlink feed
            (((price >= feedPrice ? price - feedPrice : feedPrice - price) *
                PRECISION *
                100) /
                feedPrice <=
                feedMaxDeviationP)
        ) {
            IGambitTradingCallbacksV1.AggregatorAnswer memory a;

            a.orderId = orderId;
            a.price = price;
            a.conf = conf;
            a.confMultiplierP = pairsStorage.pairConfMultiplierP(r.pairIndex);

            IGambitTradingCallbacksV1 c = IGambitTradingCallbacksV1(
                storageT.callbacks()
            );

            if (r.orderType == OrderType.MARKET_OPEN) {
                c.openTradeMarketCallback(a);
            } else if (r.orderType == OrderType.MARKET_CLOSE) {
                c.closeTradeMarketCallback(a);
            } else if (r.orderType == OrderType.LIMIT_OPEN) {
                c.executeNftOpenOrderCallback(a);
            } else if (r.orderType == OrderType.LIMIT_CLOSE) {
                c.executeNftCloseOrderCallback(a);
            } else if (r.orderType == OrderType.UPDATE_SL) {
                c.updateSlCallback(a);
            } else {
                c.removeCollateralCallback(a);
            }

            delete orders[orderId];
            success = true;

            emit PriceReceived(
                orderId,
                msg.sender,
                r.pairIndex,
                price,
                feedPrice
            );
        }
    }

    /// @dev update pyth network's price and get the latest price
    function updatePrice(
        uint orderId,
        PythStructs.Price calldata pythPrice
    )
        internal
        returns (
            uint256 feedMaxDeviationP,
            uint256 feedPrice,
            uint256 price,
            uint256 conf
        )
    {
        Order memory r = orders[orderId];

        if (!r.initiated) {
            return (0, 0, 0, 0);
        }

        IGambitPairsStorageV1.Feed memory f = pairsStorage.pairFeed(
            r.pairIndex
        );
        feedMaxDeviationP = f.maxDeviationP;

        // Price from Pyth network
        if (block.timestamp - pythPrice.publishTime > PYTH_PRICE_AGE)
            revert GambitErrorsV1.PythPriceTooOld();
        if (pythPrice.price <= 0) revert GambitErrorsV1.InvalidPythPrice();
        if (pythPrice.expo > 0) revert GambitErrorsV1.InvalidPythExpo();
        cngCol.reportPrice(orderId, r.pairIndex, pythPrice);

        // parse pyth price
        price =
            (uint(uint64(pythPrice.price)) * PRECISION) /
            (10 ** uint(uint32(-pythPrice.expo)));
        conf =
            (uint(pythPrice.conf) * PRECISION) /
            (10 ** uint(uint32(-pythPrice.expo)));

        // Price from Chainlink
        if (enableChainlinkFeed && f.feed1 != address(0)) {
            // fetch price
            (, int feedPrice1, , , ) = ChainlinkFeedInterfaceV5(f.feed1)
                .latestRoundData();
            if (feedPrice1 <= 0) revert GambitErrorsV1.InvalidChainlinkPrice();
            feedPrice = uint(feedPrice1);

            // parse price
            if (
                f.feedCalculation ==
                IGambitPairsStorageV1.FeedCalculation.DEFAULT
            ) {
                feedPrice = uint((feedPrice * PRECISION) / 1e8);
            } else if (
                f.feedCalculation ==
                IGambitPairsStorageV1.FeedCalculation.INVERT
            ) {
                feedPrice = uint((PRECISION * 1e8) / feedPrice);
            } else {
                if (f.feed2 == address(0)) {
                    revert GambitErrorsV1.InvalidChainlinkFeed();
                }
                (, int feedPrice2, , , ) = ChainlinkFeedInterfaceV5(f.feed2)
                    .latestRoundData();
                if (feedPrice2 <= 0) {
                    revert GambitErrorsV1.InvalidChainlinkPrice();
                }
                feedPrice = uint((feedPrice * PRECISION) / uint(feedPrice2));
            }
        }
    }

    // Manage pending SL orders
    function storePendingSlOrder(
        uint orderId,
        PendingSl calldata p
    ) external onlyTrading {
        pendingSlOrders[orderId] = p;
    }

    function unregisterPendingSlOrder(uint orderId) external {
        if (msg.sender != storageT.callbacks())
            revert GambitErrorsV1.NotCallbacks();
        delete pendingSlOrders[orderId];
    }

    // Claim back ETH (if contract will be replaced for example)
    function claimBackETH() external onlyGov {
        (bool s, ) = payable(storageT.gov()).call{value: address(this).balance}(
            ""
        );
        require(s, "FAILED_TO_TRANSFER");
    }

    // Storage compatibility
    function openFeeP(uint pairIndex) external view returns (uint) {
        return pairsStorage.pairOpenFeeP(pairIndex);
    }
}

