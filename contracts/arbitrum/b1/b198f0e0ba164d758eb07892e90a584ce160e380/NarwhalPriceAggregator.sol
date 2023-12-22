// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./PairInfoInterface.sol";
import "./NarwhalReferralInterface.sol";
import "./LimitOrdersInterface.sol";
import "./IOracle.sol";
import "./CallbacksInterface.sol";
import "./LpInterfaceV5.sol";
import "./FullMath.sol";

import "./AbstractPyth.sol";
import "./PythStructs.sol";
import "./SafeMath.sol";

interface INarwhal {
    function tempSlippage() external view returns (uint256);

    function tempSpreadReduction() external view returns (uint256);

    function tempSL() external view returns (uint256);

    function isLimitOrder() external view returns (bool);

    function tempOrderId() external view returns (uint256);
}

interface IPythTestnet {
    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    function getUpdateFee(
        bytes[] calldata updateData
    ) external view returns (uint feeAmount);

    function queryPriceFeed(
        bytes32 id
    ) external view returns (PythStructs.PriceFeed memory priceFeed);
    
    function getPriceNoOlderThan(
        bytes32 id,
        uint age
    ) external view returns (PythStructs.Price memory price);

    function getPriceUnsafe(
        bytes32 id
    ) external view returns (PythStructs.Price memory price);

    function priceFeedExists(
        bytes32 id
    ) external view returns (bool);
    
}

interface IUniswapOracle {
    function consult(
        address token,
        uint256 amountIn
    ) external view returns (uint256 amountOut);
}

contract NarwhalPriceAggregator {
    using FixedPoint for *;
    using SafeMath for uint256;

    // Contracts (constant)
    StorageInterface public immutable storageT;
    address public PythOracle;
    address public NarwhalTrading;
    // Contracts (adjustable)
    address public pairsStorage;
    bytes32 public USDTFeed;

    // Params (constant)
    uint256 constant PRECISION = 1e10;
    uint256 public age = 15; //seconds price confidence

    // Custom data types
    enum OrderType {
        MARKET_OPEN,
        MARKET_CLOSE,
        LIMIT_OPEN,
        LIMIT_CLOSE,
        UPDATE_SL
    }

    struct Order {
        uint pairIndex;
        OrderType orderType;
        uint pythFeePerNode;
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

    struct PendingMarket {
        uint block;
        uint wantedPrice;
        uint slippageP;
        uint spreadReductionP;
        uint tokenId;
    }

    mapping(uint => Order) public orders;
    mapping(uint => uint[]) public ordersAnswers;
    mapping(uint => PendingSl) public pendingSlOrders;

    // Events
    event PairsStorageUpdated(address value);
    event USDTFeedSet(bytes32 indexed feed);
    event OracleSet(address indexed oracle);
    event AgeSet(uint256 age);
    event NarwhalTradingSet(address indexed NarwhalTrading);

    constructor(
        StorageInterface _storageT,
        address _pairsStorage,
        address _PythOracle,
        bytes32 _usdtFeed
    ) {
        require(
            address(_storageT) != address(0) &&
                address(_pairsStorage) != address(0) &&
                address(_PythOracle) != address(0),
            "WRONG_PARAMS"
        );

        storageT = _storageT;
        PythOracle = _PythOracle;
        pairsStorage = _pairsStorage;
        USDTFeed = _usdtFeed;
        require(IPythTestnet(PythOracle).priceFeedExists(USDTFeed),"INCORRECT_PRICE_FEED");
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
    function updatePairsStorage(address value) external onlyGov {
        require(address(value) != address(0), "VALUE_0");

        pairsStorage = value;

        emit PairsStorageUpdated(address(value));
    }

    function setUSDTFeed(bytes32 _feed) public onlyGov {
        require(IPythTestnet(PythOracle).priceFeedExists(_feed),"INCORRECT_PRICE_FEED");
        USDTFeed = _feed;
        emit USDTFeedSet(_feed);
    }

    function setOracle(address _oracle) public onlyGov {
        require(_oracle != address(0), "ZERO_ADDRESS");
        PythOracle = _oracle;
        emit OracleSet(_oracle);
    }

    function setAge(uint256 _age) public onlyGov {
        require(_age <= 60, "Too much");
        age = _age;
        emit AgeSet(_age);
    }

    function setNarwhalTrading(address _NarwhalTrading) public onlyGov {
        require(_NarwhalTrading != address(0), "ZERO_ADDRESS");
        NarwhalTrading = _NarwhalTrading;
        emit NarwhalTradingSet(_NarwhalTrading);
    }
    
    function tokenPriceUSDT() public view returns (uint256) {
        //testnet
        // PythStructs.Price memory priceP = IPythTestnet(PythOracle)
        //    .getPriceUnsafe(USDTFeed);
        //mainnet
        PythStructs.Price memory priceP = IPythTestnet(PythOracle)
             .getPriceNoOlderThan(USDTFeed,age);
        uint256 price = uint256(uint64(priceP.price));
        require(price != 0, "PRICE_FEED_ERROR");
        uint256 convertedNumber = price * 1e10;
        return convertedNumber;
    }

    function beforeGetPriceLimit(
        StorageInterface.Trade memory t
    ) public onlyTrading returns (uint256) {
        (, , uint orderId) = PairsStorageInterface(pairsStorage).pairJob(
            t.pairIndex
        );
        return (orderId);
    }

    function updatePriceFeed(uint256 pairIndex,bytes[] calldata updateData) public payable onlyTrading returns (uint256) {
        PairsStorageInterface.Feed memory f = PairsStorageInterface(
            pairsStorage
        ).pairFeed(pairIndex);

        IPythTestnet(PythOracle).updatePriceFeeds{
            value: getPythFee(updateData)
        }(updateData);

        // //mainnet
         PythStructs.Price memory priceP = IPythTestnet(PythOracle)
             .getPriceNoOlderThan(f.feed1,age);

        //testnet
        // PythStructs.Price memory priceP = IPythTestnet(PythOracle)
        //    .getPriceUnsafe(f.feed1);

        uint256 convertedNumber = uint256(uint64(priceP.price));
        int32 expRefactor = priceP.expo + 18;
        uint256 factor;
        if (expRefactor > 0) {
            factor = tenPow(expRefactor);
        } else {
            revert("Check the feed decimals");
        }
        uint256 precisionPrice = convertedNumber * (factor);
        return (precisionPrice);
    }

    // On-demand price request to oracles network
    function getPrice(
        OrderType orderType,
        bytes[] calldata updateData,
        StorageInterface.Trade memory t
    ) public onlyTrading returns (uint, uint256) {
        uint orderId;
        if (INarwhal(NarwhalTrading).isLimitOrder()) {
            orderId = INarwhal(NarwhalTrading).tempOrderId();
        } else {
            orderId = beforeGetPriceLimit(t);
        }

        orders[orderId] = Order(
            t.pairIndex,
            orderType,
            getPythFee(updateData),
            true
        );

        uint256 precisionPrice = updatePriceFeed(t.pairIndex,updateData);

        if (orderType == OrderType.MARKET_CLOSE) {
            storageT.storePendingMarketOrder(
                StorageInterface.PendingMarketOrder(
                    StorageInterface.Trade(
                        t.trader,
                        t.pairIndex,
                        t.index,
                        0,
                        0,
                        0,
                        false,
                        0,
                        0,
                        0
                    ),
                    0,
                    0,
                    0,
                    0,
                    0
                ),
                orderId,
                false
            );
        } else if (orderType == OrderType.MARKET_OPEN) {
            storageT.storePendingMarketOrder(
                StorageInterface.PendingMarketOrder(
                    StorageInterface.Trade(
                        t.trader,
                        t.pairIndex,
                        0,
                        0,
                        t.positionSizeUSDT,
                        0,
                        t.buy,
                        t.leverage,
                        t.tp,
                        t.sl
                    ),
                    0,
                    t.openPrice,
                    INarwhal(NarwhalTrading).tempSlippage(),
                    INarwhal(NarwhalTrading).tempSpreadReduction(),
                    0
                ),
                orderId,
                true
            );
        } else {
            storePendingSlOrder(
                orderId,
                PendingSl(
                    t.trader,
                    t.pairIndex,
                    t.index,
                    t.openPrice,
                    t.buy,
                    INarwhal(NarwhalTrading).tempSL()
                )
            );
        }

        
        fulfill(orderId, precisionPrice);
        return (orderId, precisionPrice);
    }

    function tenPow(int32 exp) internal pure returns (uint256) {
        uint256 result = 1;
        for (int32 i = 0; i < exp; i++) {
            result = result.mul(10);
        }
        return result;
    }

    // Fulfill on-demand price requests
    function fulfill(uint256 orderId, uint256 price) internal {

        Order memory r = orders[orderId];
        if (!r.initiated) {
            return;
        }

        uint[] storage answers = ordersAnswers[orderId];
        answers.push(price);

        CallbacksInterface.AggregatorAnswer memory a;
        a.orderId = orderId;
        a.price = price;
        a.spreadP = PairsStorageInterface(pairsStorage).pairSpreadP(
            r.pairIndex
        );

        CallbacksInterface c = CallbacksInterface(storageT.callbacks());
        if (r.orderType == OrderType.MARKET_OPEN) {
            c.openTradeMarketCallback(a);
        } else if (r.orderType == OrderType.MARKET_CLOSE) {
            c.closeTradeMarketCallback(a);
        } else if (r.orderType == OrderType.LIMIT_OPEN) {
            c.executeOpenOrderCallback(a);
        } else if (r.orderType == OrderType.LIMIT_CLOSE) {
            c.executeCloseOrderCallback(a);
        } else {
            c.updateSlCallback(a);
        }

        delete orders[orderId];
        delete ordersAnswers[orderId];
    }

    function getPythFee(
        bytes[] calldata updateData
    ) public view returns (uint) {
        uint256 feeAmount = IPythTestnet(PythOracle).getUpdateFee(updateData);
        return feeAmount;
    }

    function storePendingSlOrder(uint orderId, PendingSl memory p) internal {
        pendingSlOrders[orderId] = p;
    }

    function unregisterPendingSlOrder(uint orderId) external {
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");

        delete pendingSlOrders[orderId];
    }

    function openFeeP(uint pairIndex) external view returns (uint) {
        return PairsStorageInterface(pairsStorage).pairOpenFeeP(pairIndex);
    }

    function withdrawETH(address payable recipient) external onlyGov {
        require(recipient != address(0), "Invalid address");
        (bool success, ) = recipient.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    receive() external payable {}
}

