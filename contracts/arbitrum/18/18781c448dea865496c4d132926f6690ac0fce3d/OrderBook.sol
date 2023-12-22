// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Address.sol";

import "./IWETH.sol";
import "./ReentrancyGuard.sol";
import "./IUniswapV2Router01.sol";
import "./IVault.sol";
import "./IOrderBook.sol";
import "./IFeeLP.sol";


contract OrderBook is ReentrancyGuard, IOrderBook {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public PRICE_PRECISION = 1e30;
    uint256 public LP_PRECISION = 1e18;

    struct IncreaseOrder {
        address account;
        uint32 createTime;
        address purchaseToken;
        uint256 purchaseTokenAmount;
        address indexToken;
        uint256 minOut;
        uint256 sizeDelta;
        bool isLong;
        uint256 triggerPrice;
        bool triggerAboveThreshold;
        uint256 executionFee;
        uint256 insuranceLevel;
        uint256 feeLPAmount;
    }

    struct CreateIncreaseOrderParams {
        address account;
        address purchaseToken;
        uint256 purchaseTokenAmount;
        address indexToken;
        uint256 minOut;
        uint256 sizeDelta;
        bool isLong;
        uint256 triggerPrice;
        bool triggerAboveThreshold;
        uint256 executionFee;
        uint256 insuranceLevel;
        uint256 feeLPAmount;
    }

    struct DecreaseOrder {
        address account;
        uint32 createTime;
        address indexToken;
        uint256 sizeDelta;
        uint256 collateralDelta;
        bool isLong;
        uint256 triggerPrice;
        bool triggerAboveThreshold;
        uint256 executionFee;
        uint256 insuranceLevel;
        uint256 feeLPAmount;
    }

    mapping(address => mapping(uint256 => IncreaseOrder)) public increaseOrders;
    mapping(address => uint256) public increaseOrdersIndex;
    mapping(address => mapping(uint256 => DecreaseOrder)) public decreaseOrders;
    mapping(address => uint256) public decreaseOrdersIndex;

    address public gov;
    address public weth;
    address public LP;
    address public FeeLP;
    address public usdc;
    address public vault;
    uint256 public minExecutionFee;
    bool public isInitialized = false;
    address public router;

    event CreateIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address purchaseToken,
        uint256 purchaseTokenAmount,
        address indexToken,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee,
        uint256 insuranceLevel,
        uint256 feeLPAmount
    );
    event CancelIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address purchaseToken,
        uint256 purchaseTokenAmount,
        address indexToken,
        uint256 minOut,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee,
        uint256 insuranceLevel,
        uint256 feeLPAmount
    );
    event ExecuteIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address purchaseToken,
        uint256 purchaseTokenAmount,
        address indexToken,
        uint256 sizeDelta,
        uint256 collateralDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee,
        uint256 executionPrice,
        uint256 insuranceLevel
    );
    event UpdateIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address indexToken,
        bool isLong,
        uint256 sizeDelta,
        uint256 triggerPrice,
        bool triggerAboveThreshold
    );

    event CreateDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address indexToken,
        uint256 sizeDelta,
        uint256 collateralDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee,
        uint256 insuranceLevel,
        uint256 feeLPAmount
    );
    event CancelDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee,
        uint256 insuranceLevel,
        uint256 feeLPAmount
    );
    event ExecuteDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address indexToken,
        uint256 sizeDelta,
        uint256 collateralDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold,
        uint256 executionFee,
        uint256 executionPrice,
        uint256 insuranceLevel
    );
    event UpdateDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold
    );

    event Initialize(
        address router,
        address vault,
        address weth,
        address LP,
        uint256 minExecutionFee
    );
    event UpdateMinExecutionFee(uint256 minExecutionFee);
    event UpdateMinPurchaseTokenAmountUsd(uint256 minPurchaseTokenAmountUsd);
    event UpdateGov(address gov);

    modifier onlyGov() {
        require(msg.sender == gov, "OrderBook: forbidden");
        _;
    }

    function initialize(
        address _router,
        address _vault,
        address _weth,
        address _LP,
        address _FeeLP,
        address _usdc,
        uint256 _minExecutionFee
    ) external {
        require(!isInitialized, "OrderBook: already initialized");
        isInitialized = true;
        gov = msg.sender;
        PRICE_PRECISION = 1e30;
        LP_PRECISION = 1e18;

        router = _router;
        vault = _vault;
        weth = _weth;
        LP = _LP;
        FeeLP = _FeeLP;
        usdc = _usdc;
        minExecutionFee = _minExecutionFee;

        IERC20(LP).safeApprove(vault, type(uint256).max);
        IERC20(usdc).safeApprove(vault, type(uint256).max);

        emit Initialize(_router, _vault, _weth, _LP, _minExecutionFee);
    }

    receive() external payable {
        require(msg.sender == weth, "OrderBook: invalid sender");
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;

        emit UpdateGov(_gov);
    }

    function cancelMultiple(
        uint256[] memory _increaseOrderIndexes,
        uint256[] memory _decreaseOrderIndexes
    ) external {
        for (uint256 i = 0; i < _increaseOrderIndexes.length; i++) {
            cancelIncreaseOrder(_increaseOrderIndexes[i]);
        }
        for (uint256 i = 0; i < _decreaseOrderIndexes.length; i++) {
            cancelDecreaseOrder(_decreaseOrderIndexes[i]);
        }
    }

    function validateTrigger(
        uint256 _triggerPrice,
        address _indexToken,
        bool _long
    ) public view {
        uint256 currentPrice = _long
            ? IVault(vault).getMaxPrice(_indexToken)
            : IVault(vault).getMaxPrice(_indexToken);

        if (_long) {
            require(
                currentPrice > _triggerPrice && _triggerPrice != 0,
                "OrderBook: _triggerPrice should less than current price"
            );
        } else {
            require(
                currentPrice < _triggerPrice,
                "OrderBook: _triggerPrice should bigger than current price"
            );
        }
    }

    function validatePositionOrderPrice(
        bool _triggerAboveThreshold,
        uint256 _triggerPrice,
        address _indexToken,
        bool _maximizePrice,
        bool _raise
    ) public view returns (uint256, bool) {
        uint256 currentPrice = _maximizePrice
            ? IVault(vault).getMaxPrice(_indexToken)
            : IVault(vault).getMinPrice(_indexToken);
        bool isPriceValid = _triggerAboveThreshold
            ? currentPrice > _triggerPrice
            : currentPrice < _triggerPrice;
        if (_raise) {
            require(isPriceValid, "OrderBook: invalid price for execution");
        }
        return (currentPrice, isPriceValid);
    }

    function getDecreaseOrder(
        address _account,
        uint256 _orderIndex
    )
        public
        view
        override
        returns (
            uint256 collateralDelta,
            address indexToken,
            uint256 sizeDelta,
            bool isLong,
            uint256 triggerPrice,
            bool triggerAboveThreshold,
            uint256 executionFee,
            uint32 createTime
        )
    {
        DecreaseOrder memory order = decreaseOrders[_account][_orderIndex];
        return (
            order.collateralDelta,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee,
            order.createTime
        );
    }

    function getIncreaseOrder(
        address _account,
        uint256 _orderIndex
    )
        public
        view
        override
        returns (
            address purchaseToken,
            uint256 purchaseTokenAmount,
            address indexToken,
            uint256 sizeDelta,
            bool isLong,
            uint256 triggerPrice,
            bool triggerAboveThreshold,
            uint256 executionFee,
            uint32 createTime
        )
    {
        IncreaseOrder memory order = increaseOrders[_account][_orderIndex];
        return (
            order.purchaseToken,
            order.purchaseTokenAmount,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee,
            order.createTime
        );
    }

    function createIncreaseOrder(
        address _purchaseToken,
        uint256 _purchaseTokenAmount,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _insuranceLevel,
        uint256 _triggerPrice,
        uint256 _executionFee
    ) external payable nonReentrant {
        bool _triggerAboveThreshold = !_isLong;
        validateTrigger(_triggerPrice, _indexToken, _isLong);

        _transferInETH();
        require(
            (msg.value == _executionFee) && (_executionFee >= minExecutionFee),
            "OrderBook: insufficient execution fee"
        );

        require(_purchaseToken == LP, "OrderBook: purchase token invalid");
        CreateIncreaseOrderParams memory p = CreateIncreaseOrderParams(
            msg.sender,
            _purchaseToken,
            _purchaseTokenAmount,
            _indexToken,
            _minOut,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            _executionFee,
            _insuranceLevel,
            0
        );

        //transfer in here first,_purchaseToken as lp only
        //add insurance
        //if sizeDelta is 0,no fee
        uint256 all = _purchaseTokenAmount;
        if (p.sizeDelta > 0) {
            require(
                p.sizeDelta <=
                    _purchaseTokenAmount.mul(IVault(vault).maxLeverage()).div(
                        2*IVault(vault).BASIS_POINTS_DIVISOR()
                    ),
                "Orderbook: leverage invalid"
            );

            all = all.add(
                _purchaseTokenAmount
                    .mul(IVault(vault).insuranceLevel(_insuranceLevel))
                    .div(IVault(vault).BASIS_POINTS_DIVISOR())
            );
            //add fee
            {
                uint256 fee = IVault(vault).getPositionFee(_sizeDelta);

                if (IFeeLP(FeeLP).balanceOf(msg.sender) >= fee) {
                    IFeeLP(FeeLP).lock(msg.sender, address(this), fee, true);
                    p.feeLPAmount = fee;
                } else {
                    all = all.add(fee);
                }
            }
        }

        IERC20(_purchaseToken).safeTransferFrom(msg.sender, address(this), all);

        _createIncreaseOrder(p);
    }

    function _createIncreaseOrder(CreateIncreaseOrderParams memory p) private {
        uint256 _orderIndex = increaseOrdersIndex[p.account];
        IncreaseOrder memory order = IncreaseOrder(
            p.account,
            uint32(block.timestamp),
            p.purchaseToken,
            p.purchaseTokenAmount,
            p.indexToken,
            p.minOut,
            p.sizeDelta,
            p.isLong,
            p.triggerPrice,
            p.triggerAboveThreshold,
            p.executionFee,
            p.insuranceLevel,
            p.feeLPAmount
        );
        increaseOrdersIndex[p.account] = _orderIndex.add(1);
        increaseOrders[p.account][_orderIndex] = order;
        emit CreateIncreaseOrder(
            p.account,
            _orderIndex,
            p.purchaseToken,
            p.purchaseTokenAmount,
            p.indexToken,
            p.minOut,
            p.sizeDelta,
            p.isLong,
            p.triggerPrice,
            p.triggerAboveThreshold,
            p.executionFee,
            p.insuranceLevel,
            p.feeLPAmount
        );
    }

    function updateIncreaseOrder(
        uint256 _orderIndex,
        uint256 _sizeDelta,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external nonReentrant {
        IncreaseOrder storage order = increaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OrderBook: non-existent order");

        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        order.sizeDelta = _sizeDelta;

        emit UpdateIncreaseOrder(
            msg.sender,
            _orderIndex,
            order.indexToken,
            order.isLong,
            _sizeDelta,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }

    function cancelIncreaseOrder(uint256 _orderIndex) public nonReentrant {
        IncreaseOrder memory order = increaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OrderBook: non-existent order");

        delete increaseOrders[msg.sender][_orderIndex];

        require(order.purchaseToken == LP, "OrderBook: purchase token invalid");

        if (order.purchaseToken == address(0)) {
            _transferOutETH(
                order.executionFee.add(order.purchaseTokenAmount),
                payable(msg.sender)
            );
        } else {
            uint256 all = order.purchaseTokenAmount;
            //add insurance
            all = all.add(
                all.mul(IVault(vault).insuranceLevel(order.insuranceLevel)).div(
                    IVault(vault).BASIS_POINTS_DIVISOR()
                )
            );
            //add fee
            if (order.feeLPAmount > 0) {
                IFeeLP(FeeLP).unlock(
                    msg.sender,
                    address(this),
                    order.feeLPAmount,
                    true
                );
            } else {
                all = all.add(IVault(vault).getPositionFee(order.sizeDelta));
            }

            IERC20(order.purchaseToken).safeTransfer(msg.sender, all);
            _transferOutETH(order.executionFee, payable(msg.sender));
        }
        emit CancelIncreaseOrder(
            order.account,
            _orderIndex,
            order.purchaseToken,
            order.purchaseTokenAmount,
            order.indexToken,
            order.minOut,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee,
            order.insuranceLevel,
            order.feeLPAmount
        );
    }

    function executeIncreaseOrder(
        address _address,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external override nonReentrant {
        IncreaseOrder memory order = increaseOrders[_address][_orderIndex];
        require(order.account != address(0), "OrderBook: non-existent order");

        // increase long should use max price
        // increase short should use min price
        (uint256 currentPrice, ) = validatePositionOrderPrice(
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken,
            order.isLong,
            true
        );

        delete increaseOrders[_address][_orderIndex];
        uint256 amountOut = order.purchaseTokenAmount;
        {
            {
                uint256 amountIn = order.purchaseTokenAmount;
                if (order.sizeDelta > 0) {
                    amountIn = amountIn.add(
                        amountIn
                            .mul(
                                IVault(vault).insuranceLevel(
                                    order.insuranceLevel
                                )
                            )
                            .div(IVault(vault).BASIS_POINTS_DIVISOR())
                    );

                    uint256 positionFee = IVault(vault).getPositionFee(
                        order.sizeDelta
                    );
                    if (order.feeLPAmount >= positionFee) {
                        IFeeLP(FeeLP).burnLocked(
                            order.account,
                            address(this),
                            order.feeLPAmount,
                            true
                        );
                    } else {
                        amountIn = amountIn.add(positionFee);
                    }
                }
                IERC20(order.purchaseToken).safeTransfer(vault, amountIn);
            }

            IVault(vault).increasePosition(
                order.account,
                order.indexToken,
                order.sizeDelta,
                amountOut,
                order.isLong,
                order.insuranceLevel,
                order.feeLPAmount
            );

            // pay executor
            _transferOutETH(order.executionFee, _feeReceiver);
            emit ExecuteIncreaseOrder(
                order.account,
                _orderIndex,
                order.purchaseToken,
                order.purchaseTokenAmount,
                order.indexToken,
                order.sizeDelta,
                amountOut,
                order.isLong,
                order.triggerPrice,
                order.triggerAboveThreshold,
                order.executionFee,
                currentPrice,
                order.insuranceLevel
            );
        }
    }

    function createDecreaseOrder(
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _insuranceLevel,
        uint256 _triggerPrice,
        uint256 _executionFee
    ) external payable nonReentrant {
        uint256 currentPrice = !_isLong
            ? IVault(vault).getMaxPrice(_indexToken)
            : IVault(vault).getMinPrice(_indexToken);
        bool _triggerAboveThreshold = _triggerPrice > currentPrice;

        _transferInETH();

        require(
            (msg.value == _executionFee) && (msg.value >= minExecutionFee),
            "OrderBook: insufficient execution fee"
        );

        uint256 feeLPAmount;
        if(_sizeDelta >0){
            uint256 fee = IVault(vault).getPositionFee(_sizeDelta);
            if (IFeeLP(FeeLP).balanceOf(msg.sender) >= fee) {
                IFeeLP(FeeLP).lock(msg.sender, address(this), fee, false);
                feeLPAmount = fee;
            }
        }
        _createDecreaseOrder(
            msg.sender,
            _indexToken,
            _sizeDelta,
            _collateralDelta,
            _isLong,
            _insuranceLevel,
            _triggerPrice,
            _triggerAboveThreshold,
            feeLPAmount
        );
    }

    function _createDecreaseOrder(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _insuranceLevel,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold,
        uint256 feeLPAmount
    ) private {
        uint256 _orderIndex = decreaseOrdersIndex[_account];
        DecreaseOrder memory order = DecreaseOrder(
            _account,
            uint32(block.timestamp),
            _indexToken,
            _sizeDelta,
            _collateralDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            msg.value,
            _insuranceLevel,
            feeLPAmount
        );
        decreaseOrdersIndex[_account] = _orderIndex.add(1);
        decreaseOrders[_account][_orderIndex] = order;

        emit CreateDecreaseOrder(
            _account,
            _orderIndex,
            _indexToken,
            _sizeDelta,
            _collateralDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            msg.value,
            _insuranceLevel,
            feeLPAmount
        );
    }

    function executeDecreaseOrder(
        address _address,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external override nonReentrant {
        DecreaseOrder memory order = decreaseOrders[_address][_orderIndex];
        require(order.account != address(0), "OrderBook: non-existent order");

        // decrease long should use min price
        // decrease short should use max price
        (uint256 currentPrice, ) = validatePositionOrderPrice(
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken,
            !order.isLong,
            true
        );

        delete decreaseOrders[_address][_orderIndex];

        if (
            order.sizeDelta> 0 && order.feeLPAmount >= IVault(vault).getPositionFee(order.sizeDelta)
        ) {
            IFeeLP(FeeLP).burnLocked(
                order.account,
                address(this),
                order.feeLPAmount,
                false
            );
        }
        (, uint256 amountOut) = IVault(vault).decreasePosition(
            order.account,
            order.indexToken,
            order.sizeDelta,
            order.collateralDelta,
            order.isLong,
            order.account,
            order.insuranceLevel,
            order.feeLPAmount
        );

        // pay executor
        _transferOutETH(order.executionFee, _feeReceiver);
        emit ExecuteDecreaseOrder(
            order.account,
            _orderIndex,
            order.indexToken,
            order.sizeDelta,
            amountOut,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee,
            currentPrice,
            order.insuranceLevel
        );
    }

    function cancelDecreaseOrder(uint256 _orderIndex) public nonReentrant {
        DecreaseOrder memory order = decreaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OrderBook: non-existent order");

        if (order.feeLPAmount > 0) {
            IFeeLP(FeeLP).unlock(
                msg.sender,
                address(this),
                order.feeLPAmount,
                false
            );
        }

        delete decreaseOrders[msg.sender][_orderIndex];
        _transferOutETH(order.executionFee, payable(msg.sender));

        emit CancelDecreaseOrder(
            order.account,
            _orderIndex,
            order.collateralDelta,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.triggerAboveThreshold,
            order.executionFee,
            order.insuranceLevel,
            order.feeLPAmount
        );
    }

    function updateDecreaseOrder(
        uint256 _orderIndex,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external nonReentrant {
        DecreaseOrder storage order = decreaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OrderBook: non-existent order");

        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        order.sizeDelta = _sizeDelta;
        order.collateralDelta = _collateralDelta;

        emit UpdateDecreaseOrder(
            msg.sender,
            _orderIndex,
            _collateralDelta,
            order.indexToken,
            _sizeDelta,
            order.isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }

    function _transferInETH() private {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    function _transferOutETH(
        uint256 _amountOut,
        address payable _receiver
    ) private {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    function setTokenVault(
        address _weth,
        address _LP,
        address _usdc,
        address _vault
    ) external onlyGov {
        weth = _weth;
        LP = _LP;
        usdc = _usdc;
        vault = _vault;

        IERC20(LP).approve(vault, type(uint256).max);
        IERC20(usdc).approve(vault, type(uint256).max);
    }

    function setRouter(address _router) external onlyGov {
        router = _router;
    }

    function setMinExecutionFee(uint256 _minExecutionFee) external onlyGov {
        minExecutionFee = _minExecutionFee;
    }
}

