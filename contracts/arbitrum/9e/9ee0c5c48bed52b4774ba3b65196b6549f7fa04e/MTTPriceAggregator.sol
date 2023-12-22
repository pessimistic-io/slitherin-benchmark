// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "./ChainlinkClient.sol";
import "./TWAPPriceGetter.sol";

import "./CallbacksInterfaceV6_2.sol";
import "./ChainlinkFeedInterfaceV5.sol";
import "./StorageInterfaceV5.sol";

contract MTTPriceAggregator is ChainlinkClient, TWAPPriceGetter {
    using Chainlink for Chainlink.Request;

    // Contracts (constant)
    StorageInterfaceV5 public immutable storageT;

    // Contracts (adjustable)
    PairsStorageInterfaceV6 public pairsStorage;
    ChainlinkFeedInterfaceV5 public linkPriceFeed;

    // Params (constant)
    uint256 constant PRECISION = 1e10;
    uint256 constant MAX_ORACLE_NODES = 20;
    uint256 constant MIN_ANSWERS = 1;
    uint256 private fakeFeedPrice = 0; //should remove on mainnet
    uint256 public minAnswers;

    // Params (adjustable)

    // Custom data types
    enum OrderType {
        MARKET_OPEN,
        MARKET_CLOSE,
        LIMIT_OPEN,
        LIMIT_CLOSE,
        UPDATE_SL
    }

    struct Order {
        uint256 pairIndex;
        OrderType orderType;
        uint256 linkFeePerNode;
        bool initiated;
    }

    struct PendingSl {
        address trader;
        uint256 pairIndex;
        uint256 index;
        uint256 openPrice;
        bool buy;
        uint256 newSl;
    }

    // State
    address[] public nodes;

    mapping(uint256 => Order) public orders;
    mapping(bytes32 => uint256) public orderIdByRequest;
    mapping(uint256 => uint256[]) public ordersAnswers;

    mapping(uint256 => PendingSl) public pendingSlOrders;

    // Events
    event PairsStorageUpdated(address value);
    event LinkPriceFeedUpdated(address value);
    event MinAnswersUpdated(uint256 value);

    event NodeAdded(uint256 index, address value);
    event NodeReplaced(uint256 index, address oldNode, address newNode);
    event NodeRemoved(uint256 index, address oldNode);

    event PriceRequested(
        uint256 indexed orderId,
        bytes32 indexed job,
        uint256 indexed pairIndex,
        OrderType orderType,
        uint256 nodesCount,
        uint256 linkFeePerNode
    );

    event PriceReceived(
        bytes32 request,
        uint256 indexed orderId,
        address indexed node,
        uint256 indexed pairIndex,
        uint256 price,
        uint256 referencePrice,
        uint256 linkFee
    );

    constructor(
        address _linkToken,
        IUniswapV3Pool _tokenDaiLp,
        uint32 _twapInterval,
        StorageInterfaceV5 _storageT,
        PairsStorageInterfaceV6 _pairsStorage,
        ChainlinkFeedInterfaceV5 _linkPriceFeed,
        uint256 _minAnswers,
        address[] memory _nodes
    )
        TWAPPriceGetter(
            _tokenDaiLp,
            address(_storageT.token()),
            _twapInterval,
            PRECISION
        )
    {
        require(
            address(_storageT) != address(0) &&
                address(_pairsStorage) != address(0) &&
                address(_linkPriceFeed) != address(0) &&
                _minAnswers >= MIN_ANSWERS &&
                _minAnswers % 2 == 1 &&
                //_nodes.length > 0 &&
                _linkToken != address(0),
            "WRONG_PARAMS"
        );

        storageT = _storageT;

        pairsStorage = _pairsStorage;
        linkPriceFeed = _linkPriceFeed;

        minAnswers = _minAnswers;
        nodes = _nodes;

        setChainlinkToken(_linkToken);
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyTrading() {
        require(msg.sender == storageT.trading(), "TRADING_ONLY");
        _;
    }
    modifier onlyCallbacks() {
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");
        _;
    }

    // Manage contracts
    function updatePairsStorage(PairsStorageInterfaceV6 value)
        external
        onlyGov
    {
        require(address(value) != address(0), "VALUE_0");

        pairsStorage = value;

        emit PairsStorageUpdated(address(value));
    }

    function updateLinkPriceFeed(ChainlinkFeedInterfaceV5 value)
        external
        onlyGov
    {
        require(address(value) != address(0), "VALUE_0");

        linkPriceFeed = value;

        emit LinkPriceFeedUpdated(address(value));
    }

    // Manage TWAP variables
    function updateUniV3Pool(IUniswapV3Pool _uniV3Pool) external onlyGov {
        _updateUniV3Pool(_uniV3Pool);
    }

    function updateTwapInterval(uint32 _twapInterval) external onlyGov {
        _updateTwapInterval(_twapInterval);
    }

    // Manage params
    function updateMinAnswers(uint256 value) external onlyGov {
        require(value >= MIN_ANSWERS, "MIN_ANSWERS");
        require(value % 2 == 1, "EVEN");

        minAnswers = value;

        emit MinAnswersUpdated(value);
    }

    // Manage nodes
    function addNode(address a) external onlyGov {
        require(a != address(0), "VALUE_0");
        require(nodes.length < MAX_ORACLE_NODES, "MAX_ORACLE_NODES");

        for (uint256 i = 0; i < nodes.length; i++) {
            require(nodes[i] != a, "ALREADY_LISTED");
        }

        nodes.push(a);

        emit NodeAdded(nodes.length - 1, a);
    }

    function replaceNode(uint256 index, address a) external onlyGov {
        require(index < nodes.length, "WRONG_INDEX");
        require(a != address(0), "VALUE_0");

        emit NodeReplaced(index, nodes[index], a);

        nodes[index] = a;
    }

    function removeNode(uint256 index) external onlyGov {
        require(index < nodes.length, "WRONG_INDEX");

        emit NodeRemoved(index, nodes[index]);

        nodes[index] = nodes[nodes.length - 1];
        nodes.pop();
    }

    function setTestnet(uint256 _fakeFeedPrice) external onlyGov {
        fakeFeedPrice = _fakeFeedPrice;
    }

    // On-demand price request to oracles network
    function getPrice(
        uint256 pairIndex,
        OrderType orderType,
        uint256 leveragedPosDai
    ) external onlyTrading returns (uint256) {
        (
            string memory from,
            string memory to,
            bytes32 job,
            uint256 orderId
        ) = pairsStorage.pairJob(pairIndex);

        if (nodes.length == 0) {
            emit PriceRequested(
                orderId,
                job,
                pairIndex,
                orderType,
                nodes.length,
                0
            );
            return orderId;
        }
        uint256 linkFeePerNode = linkFee(pairIndex, leveragedPosDai) /
            nodes.length;

        Chainlink.Request memory linkRequest = buildChainlinkRequest(
            job,
            address(this),
            this.fulfill.selector
        );

        linkRequest.add("from", from);
        linkRequest.add("to", to);

        orders[orderId] = Order(pairIndex, orderType, linkFeePerNode, true);

        for (uint256 i = 0; i < nodes.length; i++) {
            orderIdByRequest[
                sendChainlinkRequestTo(nodes[i], linkRequest, linkFeePerNode)
            ] = orderId;
        }

        emit PriceRequested(
            orderId,
            job,
            pairIndex,
            orderType,
            nodes.length,
            linkFeePerNode
        );

        return orderId;
    }

    function emptyNodeFulFill(
        uint256 pairIndex,
        uint256 orderId,
        OrderType orderType
    ) external onlyTrading {
        if (nodes.length != 0) {
            return;
        }
        PairsStorageInterfaceV6.Feed memory f = pairsStorage.pairFeed(
            pairIndex
        );

        uint256 feedPrice;
        if (fakeFeedPrice == 0) {
            (, int256 feedPrice1, , , ) = ChainlinkFeedInterfaceV5(f.feed1)
                .latestRoundData();
            if (
                f.feedCalculation ==
                PairsStorageInterfaceV6.FeedCalculation.DEFAULT
            ) {
                feedPrice = uint256((feedPrice1 * int256(PRECISION)) / 1e8);
            } else if (
                f.feedCalculation ==
                PairsStorageInterfaceV6.FeedCalculation.INVERT
            ) {
                feedPrice = uint256((int256(PRECISION) * 1e8) / feedPrice1);
            } else {
                (, int256 feedPrice2, , , ) = ChainlinkFeedInterfaceV5(f.feed2)
                    .latestRoundData();
                feedPrice = uint256(
                    (feedPrice1 * int256(PRECISION)) / feedPrice2
                );
            }
        } else feedPrice = fakeFeedPrice;

        CallbacksInterfaceV6_2.AggregatorAnswer memory a;

        a.orderId = orderId;
        a.price = feedPrice;
        a.spreadP = pairsStorage.pairSpreadP(pairIndex);

        CallbacksInterfaceV6_2 c = CallbacksInterfaceV6_2(storageT.callbacks());

        if (orderType == OrderType.MARKET_OPEN) {
            c.openTradeMarketCallback(a);
        } else if (orderType == OrderType.MARKET_CLOSE) {
            c.closeTradeMarketCallback(a);
        } else if (orderType == OrderType.LIMIT_OPEN) {
            c.executeNftOpenOrderCallback(a);
        } else if (orderType == OrderType.LIMIT_CLOSE) {
            c.executeNftCloseOrderCallback(a);
        } else {
            c.updateSlCallback(a);
        }

        emit PriceReceived(
            bytes32(block.timestamp),
            orderId,
            msg.sender,
            pairIndex,
            feedPrice,
            feedPrice,
            0
        );
    }

    // Fulfill on-demand price requests
    function fulfill(bytes32 requestId, uint256 price)
        external
        recordChainlinkFulfillment(requestId)
    {
        uint256 orderId = orderIdByRequest[requestId];
        Order memory r = orders[orderId];

        delete orderIdByRequest[requestId];

        if (!r.initiated) {
            return;
        }

        uint256[] storage answers = ordersAnswers[orderId];
        uint256 feedPrice;

        PairsStorageInterfaceV6.Feed memory f = pairsStorage.pairFeed(
            r.pairIndex
        );
        (, int256 feedPrice1, , , ) = ChainlinkFeedInterfaceV5(f.feed1)
            .latestRoundData();

        if (
            f.feedCalculation == PairsStorageInterfaceV6.FeedCalculation.DEFAULT
        ) {
            feedPrice = uint256((feedPrice1 * int256(PRECISION)) / 1e8);
        } else if (
            f.feedCalculation == PairsStorageInterfaceV6.FeedCalculation.INVERT
        ) {
            feedPrice = uint256((int256(PRECISION) * 1e8) / feedPrice1);
        } else if (
            f.feedCalculation ==
            PairsStorageInterfaceV6.FeedCalculation.UNDEFINED
        ) {
            //thangtest only testnet UNDEFINED
            feedPrice = price;
        } else {
            (, int256 feedPrice2, , , ) = ChainlinkFeedInterfaceV5(f.feed2)
                .latestRoundData();
            feedPrice = uint256((feedPrice1 * int256(PRECISION)) / feedPrice2);
        }

        if (
            price == 0 ||
            ((price >= feedPrice ? price - feedPrice : feedPrice - price) *
                PRECISION *
                100) /
                feedPrice <=
            f.maxDeviationP
        ) {
            answers.push(price);

            if (answers.length == minAnswers) {
                CallbacksInterfaceV6_2.AggregatorAnswer memory a;

                a.orderId = orderId;
                a.price = median(answers);
                a.spreadP = pairsStorage.pairSpreadP(r.pairIndex);

                CallbacksInterfaceV6_2 c = CallbacksInterfaceV6_2(
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
                } else {
                    c.updateSlCallback(a);
                }

                delete orders[orderId];
                delete ordersAnswers[orderId];
            }

            emit PriceReceived(
                requestId,
                orderId,
                msg.sender,
                r.pairIndex,
                price,
                feedPrice,
                r.linkFeePerNode
            );
        }
    }

    // Calculate LINK fee for each request
    function linkFee(uint256 pairIndex, uint256 leveragedPosDai)
        public
        view
        returns (uint256)
    {
        (, int256 linkPriceUsd, , , ) = linkPriceFeed.latestRoundData();

        return
            (pairsStorage.pairOracleFeeP(pairIndex) * leveragedPosDai * 1e8) /
            uint256(linkPriceUsd) /
            PRECISION /
            100;
    }

    // Manage pending SL orders
    function storePendingSlOrder(uint256 orderId, PendingSl calldata p)
        external
        onlyTrading
    {
        pendingSlOrders[orderId] = p;
    }

    function unregisterPendingSlOrder(uint256 orderId) external {
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");

        delete pendingSlOrders[orderId];
    }

    // Claim back LINK tokens (if contract will be replaced for example)
    function claimBackLink() external onlyGov {
        TokenInterfaceV5 link = storageT.linkErc677();

        link.transfer(storageT.gov(), link.balanceOf(address(this)));
    }

    // Median function
    function swap(
        uint256[] memory array,
        uint256 i,
        uint256 j
    ) private pure {
        (array[i], array[j]) = (array[j], array[i]);
    }

    function sort(
        uint256[] memory array,
        uint256 begin,
        uint256 end
    ) private pure {
        if (begin >= end) {
            return;
        }

        uint256 j = begin;
        uint256 pivot = array[j];

        for (uint256 i = begin + 1; i < end; ++i) {
            if (array[i] < pivot) {
                swap(array, i, ++j);
            }
        }

        swap(array, begin, j);
        sort(array, begin, j);
        sort(array, j + 1, end);
    }

    function median(uint256[] memory array) private pure returns (uint256) {
        sort(array, 0, array.length);

        return
            array.length % 2 == 0
                ? (array[array.length / 2 - 1] + array[array.length / 2]) / 2
                : array[array.length / 2];
    }

    // Storage v5 compatibility
    function openFeeP(uint256 pairIndex) external view returns (uint256) {
        return pairsStorage.pairOpenFeeP(pairIndex);
    }
}

