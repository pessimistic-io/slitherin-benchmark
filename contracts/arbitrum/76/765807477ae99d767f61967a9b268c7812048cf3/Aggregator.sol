// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ChainlinkClient.sol";
import "./ITradingCallbacks.sol";
import "./IChainlinkFeed.sol";
import "./ITradingStorage.sol";


contract Aggregator is ChainlinkClient {
    using Chainlink for Chainlink.Request;

    uint256 constant PRECISION = 1e10;
    uint256 constant MAX_ORACLE_NODES = 20;
    uint256 constant MIN_ANSWERS = 3;

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

    ITradingStorage public storageT;
    IPairsStorage public pairsStorage;
    IChainlinkFeed public linkPriceFeed;

    address[] public nodes;
    uint256 public linkFee;
    uint256 public minAnswers;
    uint256 public stalePriceDelay;

    mapping(uint256 => Order) public orders;
    mapping(bytes32 => uint256) public orderIdByRequest;
    mapping(address => mapping(uint256 => bytes32)) public orderRequestByAddressId;
    mapping(uint256 => uint256[]) public ordersAnswers;
    mapping(uint256 => PendingSl) public pendingSlOrders;

    event PairsStorageUpdated(address value);
    event LinkPriceFeedUpdated(address value);
    event MinAnswersUpdated(uint256 value);

    event NodeAdded(uint index, address value);
    event NodeReplaced(uint index, address oldNode, address newNode);
    event NodeRemoved(uint index, address oldNode);

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
        uint indexed orderId,
        address indexed node,
        uint indexed pairIndex,
        uint price,
        uint referencePrice,
        uint linkFee
    );

    error AggregatorWrongParameters();
    error AggregatorWrongIndex();
    error AggregatorInvalidGovAddress(address account);
    error AggregatorInvalidTradingContract(address account);
    error AggregatorInvalidCallbacksContract(address account);
    error AggregatorInvalidAddress(address account);
    error AggregatorAlreadyListed();
    error AggregatorInvalidOraclePrice();

    modifier onlyGov() {
        if (msg.sender != storageT.gov()) {
            revert AggregatorInvalidGovAddress(msg.sender);
        }
        _;
    }
    modifier onlyTrading() {
        if (msg.sender != storageT.trading()) {
            revert AggregatorInvalidTradingContract(msg.sender);
        }
        _;
    }
    modifier onlyCallbacks() {
        if (msg.sender != storageT.callbacks()) {
            revert AggregatorInvalidCallbacksContract(msg.sender);
        }
        _;
    }


    constructor(
        address _linkToken,
        ITradingStorage _storageT,
        IPairsStorage _pairsStorage,
        IChainlinkFeed _linkPriceFeed,
        uint256 _minAnswers,
        address[] memory _nodes
    ) {
        if (address(_storageT) == address(0) ||
            address(_pairsStorage) == address(0) ||
            address(_linkPriceFeed) == address(0) ||
            _minAnswers < MIN_ANSWERS ||
            _minAnswers % 2 != 1 ||
            _nodes.length == 0 ||
            _linkToken == address(0)) {
            revert AggregatorWrongParameters();
        }

        storageT = _storageT;
        pairsStorage = _pairsStorage;
        linkPriceFeed = _linkPriceFeed;
        minAnswers = _minAnswers;
        nodes = _nodes;
        setChainlinkToken(_linkToken);
    }


    function updatePairsStorage(IPairsStorage value) external onlyGov {
        if (address(value) == address(0)) {
            revert AggregatorInvalidAddress(address(0));
        }

        pairsStorage = value;
        emit PairsStorageUpdated(address(value));
    }

    function updateLinkPriceFeed(
        IChainlinkFeed value
    ) external onlyGov {
        if (address(value) == address(0)) {
            revert AggregatorInvalidAddress(address(0));
        }

        linkPriceFeed = value;
        emit LinkPriceFeedUpdated(address(value));
    }

    function updateMinAnswers(uint value) external onlyGov {
        if (value < MIN_ANSWERS || value % 2 != 1) {
            revert AggregatorWrongParameters();
        }

        minAnswers = value;
        emit MinAnswersUpdated(value);
    }

    function setStalePriceDelay(uint256 _stalePriceDelay) external onlyGov returns (bool) {
      if (_stalePriceDelay < 1 hours) revert AggregatorWrongParameters();
      stalePriceDelay = _stalePriceDelay;
      return true;
    }

    function setLinkFee(uint256 _fee) external onlyGov {
        linkFee = _fee;
    }

    function addNode(address a) external onlyGov {
        if (a == address(0)) {
            revert AggregatorInvalidAddress(address(0));
        }
        if (nodes.length >= MAX_ORACLE_NODES) {
            revert AggregatorWrongParameters();
        }

        for (uint i = 0; i < nodes.length; i++) {
            if (nodes[i] == a) {
                revert AggregatorAlreadyListed();
            }
        }

        nodes.push(a);
        emit NodeAdded(nodes.length - 1, a);
    }

    function replaceNode(uint index, address a) external onlyGov {
        if (a == address(0)) {
            revert AggregatorInvalidAddress(address(0));
        }
        if (index >= nodes.length) {
            revert AggregatorWrongIndex();
        }

        nodes[index] = a;
        emit NodeReplaced(index, nodes[index], a);
    }

    function removeNode(uint index) external onlyGov {
        if (index >= nodes.length) {
            revert AggregatorWrongIndex();
        }

        emit NodeRemoved(index, nodes[index]);

        nodes[index] = nodes[nodes.length - 1];
        nodes.pop();
    }

    function getPrice(
        uint256 pairIndex,
        OrderType orderType,
        uint256
    ) external onlyTrading returns (uint256, bytes32) {
        (
            string memory from,
            string memory to,
            bytes32 job,
            uint256 orderId
        ) = pairsStorage.pairJob(pairIndex);

        Chainlink.Request memory linkRequest = buildChainlinkRequest(
            job,
            address(this),
            this.fulfill.selector
        );

        linkRequest.add("from", from);
        linkRequest.add("to", to);

        uint256 linkFeePerNode = linkFee / nodes.length;

        orders[orderId] = Order(pairIndex, orderType, linkFeePerNode, true);

        for (uint i = 0; i < nodes.length; i++) {
            bytes32 request = sendChainlinkRequestTo(
                nodes[i],
                linkRequest,
                linkFeePerNode
            );

            orderIdByRequest[request] = orderId;
            orderRequestByAddressId[nodes[i]][orderId] = request;
        }

        emit PriceRequested(
            orderId,
            job,
            pairIndex,
            orderType,
            nodes.length,
            linkFeePerNode
        );

        return (orderId, orderRequestByAddressId[nodes[0]][orderId]);
    }

    function fulfill(
        bytes32 requestId,
        uint256 price
    ) external recordChainlinkFulfillment(requestId) {
        uint256 orderId = orderIdByRequest[requestId];
        Order memory r = orders[orderId];

        delete orderIdByRequest[requestId];

        if (!r.initiated) {
            return;
        }

        uint256[] storage answers = ordersAnswers[orderId];
        uint256 feedPrice;

        IPairsStorage.Feed memory f = pairsStorage.pairFeed(r.pairIndex);
        (, int256 feedPrice1, , uint256 updatedAt1, ) = IChainlinkFeed(f.feed1)
            .latestRoundData();
        feedPriceVerification(feedPrice1, updatedAt1);

        if (f.feedCalculation == IPairsStorage.FeedCalculation.DEFAULT) {
            feedPrice = uint256((feedPrice1 * int256(PRECISION)) / 1e8);
        } else if (f.feedCalculation == IPairsStorage.FeedCalculation.INVERT) {
            feedPrice = uint256((int256(PRECISION) * 1e8) / feedPrice1);
        } else {
            (, int256 feedPrice2, , uint256 updatedAt2, ) = IChainlinkFeed(f.feed2)
                .latestRoundData();
        feedPriceVerification(feedPrice2, updatedAt2);

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
                ITradingCallbacks.AggregatorAnswer memory a;

                a.orderId = orderId;
                a.price = median(answers);
                a.spreadP = pairsStorage.pairSpreadP(r.pairIndex);

                ITradingCallbacks c = ITradingCallbacks(
                    storageT.callbacks()
                );

                if (r.orderType == OrderType.MARKET_OPEN) {
                    c.openTradeMarketCallback(a);
                } else if (r.orderType == OrderType.MARKET_CLOSE) {
                    c.closeTradeMarketCallback(a);
                } else if (r.orderType == OrderType.LIMIT_OPEN) {
                    c.executeBotOpenOrderCallback(a);
                } else if (r.orderType == OrderType.LIMIT_CLOSE) {
                    c.executeBotCloseOrderCallback(a);
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

    function storePendingSlOrder(
        uint256 orderId,
        PendingSl calldata p
    ) external onlyTrading {
        pendingSlOrders[orderId] = p;
    }

    function unregisterPendingSlOrder(uint256 orderId) external {
        if (msg.sender != storageT.callbacks()) {
            revert AggregatorInvalidCallbacksContract(msg.sender);
        }

        delete pendingSlOrders[orderId];
    }

    function claimBackLink() external onlyGov {
        TokenInterface link = storageT.linkErc677();

        link.transfer(storageT.gov(), link.balanceOf(address(this)));
    }

    function openFeeP(uint256 pairIndex) external view returns (uint256) {
        return pairsStorage.pairOpenFeeP(pairIndex);
    }

    function swap(uint256[] memory array, uint256 i, uint256 j) private pure {
        (array[i], array[j]) = (array[j], array[i]);
    }

    function feedPriceVerification(int256 _answer, uint256 _updatedAt) private view {
        if (_answer < 0 || block.timestamp - _updatedAt > stalePriceDelay) revert AggregatorInvalidOraclePrice();
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
}

