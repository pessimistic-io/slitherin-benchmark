// SPDX-License-Identifier: MIT
import "./ChainlinkClient.sol";
import "./TWAPPriceGetter.sol";

import "./CallbacksInterfaceV6_4.sol";
import "./ChainlinkFeedInterfaceV5.sol";
import "./StorageInterfaceV5.sol";

import "./PackingUtils.sol";

pragma solidity 0.8.17;

contract GNSPriceAggregatorV6_4 is ChainlinkClient, TWAPPriceGetter {
    using Chainlink for Chainlink.Request;
    using PackingUtils for uint;

    // Contracts (constant)
    StorageInterfaceV5 public immutable storageT;

    // Contracts (adjustable)
    PairsStorageInterfaceV6 public pairsStorage;
    ChainlinkFeedInterfaceV5 public linkPriceFeed;

    // Params (constant)
    uint constant PRECISION = 1e10;
    uint constant MAX_ORACLE_NODES = 20;
    uint constant MIN_ANSWERS = 3;

    // Params (adjustable)
    uint public minAnswers;

    // Custom data types
    enum OrderType {
        MARKET_OPEN,
        MARKET_CLOSE,
        LIMIT_OPEN,
        LIMIT_CLOSE
    }

    struct Order {
        uint16 pairIndex;
        uint112 linkFeePerNode;
        OrderType orderType;
        bool active;
        bool isLookback;
    }

    struct LookbackOrderAnswer {
        uint64 open;
        uint64 high;
        uint64 low;
        uint64 ts;
    }

    // State
    address[] public nodes;
    bytes32[2] public jobIds;

    mapping(uint => Order) public orders;
    mapping(bytes32 => uint) public orderIdByRequest;
    mapping(uint => uint[]) public ordersAnswers;
    mapping(uint => LookbackOrderAnswer[]) public lookbackOrderAnswers;

    // Events
    event PairsStorageUpdated(address value);
    event LinkPriceFeedUpdated(address value);
    event MinAnswersUpdated(uint value);

    event NodeAdded(uint index, address value);
    event NodeReplaced(uint index, address oldNode, address newNode);
    event NodeRemoved(uint index, address oldNode);

    event JobIdUpdated(uint index, bytes32 jobId);

    event PriceRequested(
        uint indexed orderId,
        bytes32 indexed job,
        uint indexed pairIndex,
        OrderType orderType,
        uint nodesCount,
        uint linkFeePerNode,
        uint fromBlock,
        bool isLookback
    );

    event PriceReceived(
        bytes32 request,
        uint indexed orderId,
        address indexed node,
        uint16 indexed pairIndex,
        uint price,
        uint referencePrice,
        uint112 linkFee,
        bool isLookback,
        bool usedInMedian
    );

    event CallbackExecuted(CallbacksInterfaceV6_4.AggregatorAnswer a, OrderType orderType);

    constructor(
        address _linkToken,
        IUniswapV3Pool _tokenDaiLp,
        uint32 _twapInterval,
        StorageInterfaceV5 _storageT,
        PairsStorageInterfaceV6 _pairsStorage,
        ChainlinkFeedInterfaceV5 _linkPriceFeed,
        uint _minAnswers,
        address[] memory _nodes,
        bytes32[2] memory _jobIds
    ) TWAPPriceGetter(_tokenDaiLp, address(_storageT.token()), _twapInterval, PRECISION) {
        require(
            address(_storageT) != address(0) &&
                address(_pairsStorage) != address(0) &&
                address(_linkPriceFeed) != address(0) &&
                _minAnswers >= MIN_ANSWERS &&
                _minAnswers % 2 == 1 &&
                _nodes.length > 0 &&
                _linkToken != address(0),
            "WRONG_PARAMS"
        );

        storageT = _storageT;

        pairsStorage = _pairsStorage;
        linkPriceFeed = _linkPriceFeed;

        minAnswers = _minAnswers;
        nodes = _nodes;
        jobIds = _jobIds;

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
    function updatePairsStorage(PairsStorageInterfaceV6 value) external onlyGov {
        require(address(value) != address(0), "VALUE_0");

        pairsStorage = value;

        emit PairsStorageUpdated(address(value));
    }

    function updateLinkPriceFeed(ChainlinkFeedInterfaceV5 value) external onlyGov {
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
    function updateMinAnswers(uint value) external onlyGov {
        require(value >= MIN_ANSWERS, "MIN_ANSWERS");
        require(value % 2 == 1, "EVEN");

        minAnswers = value;

        emit MinAnswersUpdated(value);
    }

    // Manage nodes
    function addNode(address a) external onlyGov {
        require(a != address(0), "VALUE_0");
        require(nodes.length < MAX_ORACLE_NODES, "MAX_ORACLE_NODES");

        for (uint i; i < nodes.length; i++) {
            require(nodes[i] != a, "ALREADY_LISTED");
        }

        nodes.push(a);

        emit NodeAdded(nodes.length - 1, a);
    }

    function replaceNode(uint index, address a) external onlyGov {
        require(index < nodes.length, "WRONG_INDEX");
        require(a != address(0), "VALUE_0");

        emit NodeReplaced(index, nodes[index], a);

        nodes[index] = a;
    }

    function removeNode(uint index) external onlyGov {
        require(index < nodes.length, "WRONG_INDEX");

        emit NodeRemoved(index, nodes[index]);

        nodes[index] = nodes[nodes.length - 1];
        nodes.pop();
    }

    function setMarketJobId(bytes32 jobId) external onlyGov {
        require(jobId != bytes32(0), "VALUE_0");

        jobIds[0] = jobId;

        emit JobIdUpdated(0, jobId);
    }

    function setLimitJobId(bytes32 jobId) external onlyGov {
        require(jobId != bytes32(0), "VALUE_0");

        jobIds[1] = jobId;

        emit JobIdUpdated(1, jobId);
    }

    // On-demand price request to oracles network
    function getPrice(
        uint pairIndex,
        OrderType orderType,
        uint leveragedPosDai,
        uint fromBlock
    ) external onlyTrading returns (uint) {
        require(pairIndex <= type(uint16).max, "PAIR_OVERFLOW");

        bool isLookback = orderType == OrderType.LIMIT_OPEN || orderType == OrderType.LIMIT_CLOSE;
        bytes32 job = isLookback ? jobIds[1] : jobIds[0];

        Chainlink.Request memory linkRequest = buildChainlinkRequest(job, address(this), this.fulfill.selector);

        uint orderId;
        {
            (string memory from, string memory to, , uint _orderId) = pairsStorage.pairJob(pairIndex);
            orderId = _orderId;

            linkRequest.add("from", from);
            linkRequest.add("to", to);

            if (isLookback) {
                linkRequest.addUint("fromBlock", fromBlock);
            }
        }

        uint length;
        uint linkFeePerNode;
        {
            address[] memory _nodes = nodes;
            length = _nodes.length;
            linkFeePerNode = linkFee(pairIndex, leveragedPosDai) / length;

            require(linkFeePerNode <= type(uint112).max, "LINK_OVERFLOW");

            orders[orderId] = Order(uint16(pairIndex), uint112(linkFeePerNode), orderType, true, isLookback);
            for (uint i; i < length; ) {
                orderIdByRequest[sendChainlinkRequestTo(_nodes[i], linkRequest, linkFeePerNode)] = orderId;
                unchecked {
                    ++i;
                }
            }
        }

        emit PriceRequested(orderId, job, pairIndex, orderType, length, linkFeePerNode, fromBlock, isLookback);

        return orderId;
    }

    // Fulfill on-demand price requests
    function fulfill(bytes32 requestId, uint priceData) external recordChainlinkFulfillment(requestId) {
        uint orderId = orderIdByRequest[requestId];
        delete orderIdByRequest[requestId];

        Order memory r = orders[orderId];
        bool usedInMedian = false;

        PairsStorageInterfaceV6.Feed memory f = pairsStorage.pairFeed(r.pairIndex);
        uint feedPrice = fetchFeedPrice(f);

        if (r.active) {
            if (r.isLookback) {
                LookbackOrderAnswer memory newAnswer;
                (newAnswer.open, newAnswer.high, newAnswer.low, newAnswer.ts) = priceData.unpack256To64();

                require(
                    (newAnswer.high == 0 && newAnswer.low == 0) ||
                        (newAnswer.high >= newAnswer.open && newAnswer.low <= newAnswer.open && newAnswer.low > 0),
                    "INVALID_CANDLE"
                );

                if (
                    isPriceWithinDeviation(newAnswer.high, feedPrice, f.maxDeviationP) &&
                    isPriceWithinDeviation(newAnswer.low, feedPrice, f.maxDeviationP)
                ) {
                    usedInMedian = true;

                    LookbackOrderAnswer[] storage answers = lookbackOrderAnswers[orderId];
                    answers.push(newAnswer);

                    if (answers.length == minAnswers) {
                        CallbacksInterfaceV6_4.AggregatorAnswer memory a;
                        a.orderId = orderId;
                        (a.open, a.high, a.low) = medianLookbacks(answers);
                        a.spreadP = pairsStorage.pairSpreadP(r.pairIndex);

                        CallbacksInterfaceV6_4 c = CallbacksInterfaceV6_4(storageT.callbacks());

                        if (r.orderType == OrderType.LIMIT_OPEN) {
                            c.executeNftOpenOrderCallback(a);
                        } else {
                            c.executeNftCloseOrderCallback(a);
                        }

                        emit CallbackExecuted(a, r.orderType);

                        orders[orderId].active = false;
                        delete lookbackOrderAnswers[orderId];
                    }
                }
            } else {
                (uint64 price, , , ) = priceData.unpack256To64();

                if (isPriceWithinDeviation(price, feedPrice, f.maxDeviationP)) {
                    usedInMedian = true;

                    uint[] storage answers = ordersAnswers[orderId];
                    answers.push(price);

                    if (answers.length == minAnswers) {
                        CallbacksInterfaceV6_4.AggregatorAnswer memory a;

                        a.orderId = orderId;
                        a.price = median(answers);
                        a.spreadP = pairsStorage.pairSpreadP(r.pairIndex);

                        CallbacksInterfaceV6_4 c = CallbacksInterfaceV6_4(storageT.callbacks());

                        if (r.orderType == OrderType.MARKET_OPEN) {
                            c.openTradeMarketCallback(a);
                        } else {
                            c.closeTradeMarketCallback(a);
                        }

                        emit CallbackExecuted(a, r.orderType);

                        orders[orderId].active = false;
                        delete ordersAnswers[orderId];
                    }
                }
            }
        }

        emit PriceReceived(
            requestId,
            orderId,
            msg.sender,
            r.pairIndex,
            priceData,
            feedPrice,
            r.linkFeePerNode,
            r.isLookback,
            usedInMedian
        );
    }

    // Calculate LINK fee for each request
    function linkFee(uint pairIndex, uint leveragedPosDai) public view returns (uint) {
        (, int linkPriceUsd, , , ) = linkPriceFeed.latestRoundData();

        return (pairsStorage.pairOracleFeeP(pairIndex) * leveragedPosDai * 1e8) / uint(linkPriceUsd) / PRECISION / 100;
    }

    // Claim back LINK tokens (if contract will be replaced for example)
    function claimBackLink() external onlyGov {
        TokenInterfaceV5 link = storageT.linkErc677();

        link.transfer(storageT.gov(), link.balanceOf(address(this)));
    }

    // Utils
    function fetchFeedPrice(PairsStorageInterfaceV6.Feed memory f) private view returns (uint) {
        if (f.feed1 == address(0)) {
            return 0;
        }

        uint feedPrice;
        (, int feedPrice1, , , ) = ChainlinkFeedInterfaceV5(f.feed1).latestRoundData();

        if (f.feedCalculation == PairsStorageInterfaceV6.FeedCalculation.DEFAULT) {
            feedPrice = uint((feedPrice1 * int(PRECISION)) / 1e8);
        } else if (f.feedCalculation == PairsStorageInterfaceV6.FeedCalculation.INVERT) {
            feedPrice = uint((int(PRECISION) * 1e8) / feedPrice1);
        } else {
            (, int feedPrice2, , , ) = ChainlinkFeedInterfaceV5(f.feed2).latestRoundData();
            feedPrice = uint((feedPrice1 * int(PRECISION)) / feedPrice2);
        }

        return feedPrice;
    }

    function isPriceWithinDeviation(uint price, uint feedPrice, uint maxDeviationP) private pure returns (bool) {
        return
            price == 0 ||
            feedPrice == 0 ||
            ((price >= feedPrice ? price - feedPrice : feedPrice - price) * PRECISION * 100) / feedPrice <=
            maxDeviationP;
    }

    // Median function
    function swap(uint[] memory array, uint i, uint j) private pure {
        (array[i], array[j]) = (array[j], array[i]);
    }

    function sort(uint[] memory array, uint begin, uint end) private pure {
        if (begin >= end) {
            return;
        }

        uint j = begin;
        uint pivot = array[j];

        for (uint i = begin + 1; i < end; ++i) {
            if (array[i] < pivot) {
                swap(array, i, ++j);
            }
        }

        swap(array, begin, j);
        sort(array, begin, j);
        sort(array, j + 1, end);
    }

    function median(uint[] memory array) private pure returns (uint) {
        sort(array, 0, array.length);

        return
            array.length % 2 == 0
                ? (array[array.length / 2 - 1] + array[array.length / 2]) / 2
                : array[array.length / 2];
    }

    function medianLookbacks(
        LookbackOrderAnswer[] memory array
    ) private pure returns (uint64 open, uint64 high, uint64 low) {
        uint length = array.length;

        uint[] memory opens = new uint[](length);
        uint[] memory highs = new uint[](length);
        uint[] memory lows = new uint[](length);

        for (uint i; i < length; ) {
            opens[i] = array[i].open;
            highs[i] = array[i].high;
            lows[i] = array[i].low;

            unchecked {
                ++i;
            }
        }

        sort(opens, 0, length);
        sort(highs, 0, length);
        sort(lows, 0, length);

        bool isLengthEven = length % 2 == 0;
        uint halfLength = length / 2;

        open = uint64(isLengthEven ? (opens[halfLength - 1] + opens[halfLength]) / 2 : opens[halfLength]);
        high = uint64(isLengthEven ? (highs[halfLength - 1] + highs[halfLength]) / 2 : highs[halfLength]);
        low = uint64(isLengthEven ? (lows[halfLength - 1] + lows[halfLength]) / 2 : lows[halfLength]);
    }

    // Storage v5 compatibility
    function openFeeP(uint pairIndex) external view returns (uint) {
        return pairsStorage.pairOpenFeeP(pairIndex);
    }
}

