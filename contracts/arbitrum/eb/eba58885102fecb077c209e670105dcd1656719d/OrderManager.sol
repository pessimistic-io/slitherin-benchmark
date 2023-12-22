// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IERC20} from "./interfaces_IERC20.sol";
import {ILevelOracle} from "./ILevelOracle.sol";
import {IPool} from "./IPool.sol";
import {IOrderHook} from "./IOrderHook.sol";
import {IWETH} from "./IWETH.sol";
import {IETHUnwrapper} from "./IETHUnwrapper.sol";
import {IOrderManager} from "./IOrderManager.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {DataTypes} from "./DataTypes.sol";
import {OrderManagerStorage} from "./OrderManagerStorage.sol";

/// @title LevelOrderManager
/// @notice store and execute both leverage orders and swap orders
contract OrderManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    OrderManagerStorage,
    IOrderManager
{
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    uint8 public constant VERSION = 1;
    uint256 constant MARKET_ORDER_TIMEOUT = 5 minutes;
    uint256 constant MAX_MIN_EXECUTION_FEE = 0.01 ether;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant ETH_UNWRAPPER = 0x38EE8A935d1aCB254DC1ae3cb3E3d2De41Fe3e7B;

    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        // prevent send ETH directly to contract
        if (msg.sender != address(weth)) revert OnlyWeth();
    }

    function initialize(
        address _weth,
        address _oracle,
        address _pool,
        uint256 _minLeverageExecutionFee,
        uint256 _minSwapExecutionFee
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (_oracle == address(0)) revert ZeroAddress();
        if (_weth == address(0)) revert ZeroAddress();
        if (_pool == address(0)) revert ZeroAddress();

        _setMinExecutionFee(_minLeverageExecutionFee, _minSwapExecutionFee);
        weth = IWETH(_weth);
        oracle = ILevelOracle(_oracle);
        pool = IPool(_pool);
        nextLeverageOrderId = 1;
        nextSwapOrderId = 1;
    }

    // ============= VIEW FUNCTIONS ==============
    function getOrders(address user, uint256 skip, uint256 take)
        external
        view
        returns (uint256[] memory orderIds, uint256 total)
    {
        total = userLeverageOrders[user].length;
        uint256 toIdx = skip + take;
        toIdx = toIdx > total ? total : toIdx;
        uint256 nOrders = toIdx > skip ? toIdx - skip : 0;
        orderIds = new uint[](nOrders);
        for (uint256 i = skip; i < skip + nOrders; ++i) {
            orderIds[i] = userLeverageOrders[user][i];
        }
    }

    function getSwapOrders(address user, uint256 skip, uint256 take)
        external
        view
        returns (uint256[] memory orderIds, uint256 total)
    {
        total = userSwapOrders[user].length;
        uint256 toIdx = skip + take;
        toIdx = toIdx > total ? total : toIdx;
        uint256 nOrders = toIdx > skip ? toIdx - skip : 0;
        orderIds = new uint[](nOrders);
        for (uint256 i = skip; i < skip + nOrders; ++i) {
            orderIds[i] = userSwapOrders[user][i];
        }
    }

    // =========== MUTATIVE FUNCTIONS ==========
    function placeLeverageOrder(
        DataTypes.UpdatePositionType _updateType,
        DataTypes.Side _side,
        address _indexToken,
        address _collateralToken,
        DataTypes.OrderType _orderType,
        bytes calldata data
    ) external payable nonReentrant returns (uint256 orderId) {
        bool isIncrease = _updateType == DataTypes.UpdatePositionType.INCREASE;
        if (!pool.isValidLeverageTokenPair(_indexToken, _collateralToken, _side, isIncrease)) {
            revert InvalidLeverageTokenPair(_indexToken, _collateralToken);
        }

        bool isMarketOrder;
        if (isIncrease) {
            (orderId, isMarketOrder) =
                _createIncreasePositionOrder(_side, _indexToken, _collateralToken, _orderType, data);
        } else {
            (orderId, isMarketOrder) =
                _createDecreasePositionOrder(_side, _indexToken, _collateralToken, _orderType, data);
        }
        userLeverageOrders[msg.sender].push(orderId);
        userLeverageOrderCount[msg.sender] += 1;
    }

    function placeSwapOrder(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _price,
        bytes calldata _extradata
    ) external payable nonReentrant returns (uint256 orderId) {
        address payToken;
        (payToken, _tokenIn) = _tokenIn == ETH ? (ETH, address(weth)) : (_tokenIn, _tokenIn);
        // if token out is ETH, check wether pool support WETH
        if (!pool.canSwap(_tokenIn, _tokenOut == ETH ? address(weth) : _tokenOut)) {
            revert InvalidSwapPair();
        }
        uint256 executionFee;
        if (payToken == ETH) {
            executionFee = msg.value - _amountIn;
            weth.deposit{value: _amountIn}();
        } else {
            executionFee = msg.value;
            IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
        }

        if (executionFee < minSwapExecutionFee) {
            revert ExecutionFeeTooLow();
        }

        DataTypes.SwapOrder memory order = DataTypes.SwapOrder({
            owner: msg.sender,
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            amountIn: _amountIn,
            minAmountOut: _minOut,
            price: _price,
            executionFee: executionFee,
            status: DataTypes.OrderStatus.OPEN,
            submissionBlock: block.number,
            submissionTimestamp: block.timestamp
        });
        orderId = nextSwapOrderId;
        swapOrders[orderId] = order;
        userSwapOrders[msg.sender].push(orderId);
        userSwapOrderCount[msg.sender] += 1;
        emit SwapOrderPlaced(orderId, order);
        nextSwapOrderId = orderId + 1;
        if (address(orderHook) != address(0)) {
            orderHook.postPlaceSwapOrder(orderId, _extradata);
        }
    }

    function swap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _minAmountOut,
        bytes calldata _extradata
    ) external payable nonReentrant {
        (address outToken, address receiver) = _toToken == ETH ? (address(weth), address(this)) : (_toToken, msg.sender);

        address inToken;
        if (_fromToken == ETH) {
            _amountIn = msg.value;
            inToken = address(weth);
            weth.deposit{value: _amountIn}();
            weth.safeTransfer(address(pool), _amountIn);
        } else {
            inToken = _fromToken;
            IERC20(inToken).safeTransferFrom(msg.sender, address(pool), _amountIn);
        }

        uint256 amountOut = _doSwap(inToken, outToken, _minAmountOut, receiver, msg.sender);
        if (outToken == address(weth) && _toToken == ETH) {
            _safeUnwrapETH(amountOut, msg.sender);
        }
        emit Swap(msg.sender, _fromToken, _toToken, address(pool), _amountIn, amountOut);

        if (address(orderHook) != address(0)) {
            orderHook.postSwap(msg.sender, _extradata);
        }
    }

    function executeLeverageOrder(uint256 _orderId, address payable _feeTo) external nonReentrant {
        DataTypes.LeverageOrder memory order = leverageOrders[_orderId];
        if (order.owner == address(0) || order.status != DataTypes.OrderStatus.OPEN) {
            revert OrderNotOpen();
        }
        _validateExecution(msg.sender, order.owner, order.submissionTimestamp);

        if (order.expiresAt != 0 && order.expiresAt < block.timestamp) {
            _expiresOrder(_orderId, order);
            return;
        }

        DataTypes.UpdatePositionRequest memory request = updatePositionRequests[_orderId];
        uint256 indexPrice = _getMarkPrice(order.indexToken, request.side, request.updateType);
        bool isValid = order.triggerAboveThreshold ? indexPrice >= order.price : indexPrice <= order.price;
        if (!isValid) {
            return;
        }

        _executeLeveragePositionRequest(order, request);
        leverageOrders[_orderId].status = DataTypes.OrderStatus.FILLED;
        SafeTransferLib.safeTransferETH(_feeTo, order.executionFee);
        emit LeverageOrderExecuted(_orderId, order, request, indexPrice);
    }

    function cancelLeverageOrder(uint256 _orderId) external nonReentrant {
        DataTypes.LeverageOrder memory order = leverageOrders[_orderId];
        if (order.owner != msg.sender) {
            revert OnlyOrderOwner();
        }
        if (order.status != DataTypes.OrderStatus.OPEN) {
            revert OrderNotOpen();
        }
        DataTypes.UpdatePositionRequest memory request = updatePositionRequests[_orderId];
        leverageOrders[_orderId].status = DataTypes.OrderStatus.CANCELLED;

        SafeTransferLib.safeTransferETH(order.owner, order.executionFee);
        if (request.updateType == DataTypes.UpdatePositionType.INCREASE) {
            _refundCollateral(order.payToken, request.collateral, order.owner);
        }

        emit LeverageOrderCancelled(_orderId);
    }

    function executeSwapOrder(uint256 _orderId, address payable _feeTo) external nonReentrant {
        DataTypes.SwapOrder memory order = swapOrders[_orderId];
        if (order.owner == address(0) || order.status != DataTypes.OrderStatus.OPEN) {
            revert OrderNotOpen();
        }
        _validateExecution(msg.sender, order.owner, order.submissionTimestamp);

        swapOrders[_orderId].status = DataTypes.OrderStatus.FILLED;
        IERC20(order.tokenIn).safeTransfer(address(pool), order.amountIn);
        uint256 amountOut;
        if (order.tokenOut != ETH) {
            amountOut = _doSwap(order.tokenIn, order.tokenOut, order.minAmountOut, order.owner, order.owner);
        } else {
            amountOut = _doSwap(order.tokenIn, address(weth), order.minAmountOut, address(this), order.owner);
            _safeUnwrapETH(amountOut, order.owner);
        }
        SafeTransferLib.safeTransferETH(_feeTo, order.executionFee);
        if (amountOut < order.minAmountOut) {
            revert SlippageReached();
        }
        emit SwapOrderExecuted(_orderId, order.amountIn, amountOut);
    }

    function cancelSwapOrder(uint256 _orderId) external nonReentrant {
        DataTypes.SwapOrder memory order = swapOrders[_orderId];
        if (order.owner != msg.sender) {
            revert OnlyOrderOwner();
        }
        if (order.status != DataTypes.OrderStatus.OPEN) {
            revert OrderNotOpen();
        }
        swapOrders[_orderId].status = DataTypes.OrderStatus.CANCELLED;
        SafeTransferLib.safeTransferETH(order.owner, order.executionFee);
        IERC20(order.tokenIn).safeTransfer(order.owner, order.amountIn);
        emit SwapOrderCancelled(_orderId);
    }

    // ========= INTERNAL FUCNTIONS ==========

    function _executeLeveragePositionRequest(
        DataTypes.LeverageOrder memory _order,
        DataTypes.UpdatePositionRequest memory _request
    ) internal {
        if (_request.updateType == DataTypes.UpdatePositionType.INCREASE) {
            bool noSwap = (_order.payToken == ETH && _order.collateralToken == address(weth))
                || (_order.payToken == _order.collateralToken);

            if (!noSwap) {
                address fromToken = _order.payToken == ETH ? address(weth) : _order.payToken;
                _request.collateral =
                    _poolSwap(fromToken, _order.collateralToken, _request.collateral, 0, address(this), _order.owner);
            }

            IERC20(_order.collateralToken).safeTransfer(address(pool), _request.collateral);
            pool.increasePosition(
                _order.owner, _order.indexToken, _order.collateralToken, _request.sizeChange, _request.side
            );
        } else {
            IERC20 collateralToken = IERC20(_order.collateralToken);
            uint256 priorBalance = collateralToken.balanceOf(address(this));
            pool.decreasePosition(
                _order.owner,
                _order.indexToken,
                _order.collateralToken,
                _request.collateral,
                _request.sizeChange,
                _request.side,
                address(this)
            );
            uint256 payoutAmount = collateralToken.balanceOf(address(this)) - priorBalance;
            if (_order.collateralToken == address(weth) && _order.payToken == ETH) {
                _safeUnwrapETH(payoutAmount, _order.owner);
            } else if (_order.collateralToken != _order.payToken) {
                IERC20(_order.collateralToken).safeTransfer(address(pool), payoutAmount);
                pool.swap(_order.collateralToken, _order.payToken, 0, _order.owner, abi.encode(_order.owner));
            } else {
                collateralToken.safeTransfer(_order.owner, payoutAmount);
            }
        }
    }

    function _getMarkPrice(address _indexToken, DataTypes.Side _side, DataTypes.UpdatePositionType _updateType)
        internal
        view
        returns (uint256)
    {
        bool max = (_updateType == DataTypes.UpdatePositionType.INCREASE) == (_side == DataTypes.Side.LONG);
        return oracle.getPrice(_indexToken, max);
    }

    function _createDecreasePositionOrder(
        DataTypes.Side _side,
        address _indexToken,
        address _collateralToken,
        DataTypes.OrderType _orderType,
        bytes memory _data
    ) internal returns (uint256 orderId, bool isMarketOrder) {
        DataTypes.LeverageOrder memory order;
        DataTypes.UpdatePositionRequest memory request;
        bytes memory extradata;

        isMarketOrder = _orderType == DataTypes.OrderType.MARKET;
        if (isMarketOrder) {
            (order.price, order.payToken, request.sizeChange, request.collateral, extradata) =
                abi.decode(_data, (uint256, address, uint256, uint256, bytes));
            order.triggerAboveThreshold = _side == DataTypes.Side.LONG;
        } else {
            (
                order.price,
                order.triggerAboveThreshold,
                order.payToken,
                request.sizeChange,
                request.collateral,
                extradata
            ) = abi.decode(_data, (uint256, bool, address, uint256, uint256, bytes));
        }

        order.executionFee = msg.value;
        uint256 minExecutionFee = _calcMinLeverageExecutionFee(_collateralToken, order.payToken);
        if (order.executionFee < minExecutionFee) {
            revert ExecutionFeeTooLow();
        }

        order.owner = msg.sender;
        order.indexToken = _indexToken;
        order.collateralToken = _collateralToken;
        order.expiresAt = _orderType == DataTypes.OrderType.MARKET ? block.timestamp + MARKET_ORDER_TIMEOUT : 0;
        order.submissionBlock = block.number;
        order.submissionTimestamp = block.timestamp;
        order.status = DataTypes.OrderStatus.OPEN;

        request.updateType = DataTypes.UpdatePositionType.DECREASE;
        request.side = _side;
        orderId = nextLeverageOrderId;
        nextLeverageOrderId = orderId + 1;
        leverageOrders[orderId] = order;
        updatePositionRequests[orderId] = request;

        if (address(orderHook) != address(0)) {
            orderHook.postPlaceOrder(orderId, extradata);
        }

        emit LeverageOrderPlaced(orderId, order, request);
    }

    /// @param _data encoded order metadata, include:
    /// uint256 price trigger price of index token
    /// address payToken address the token user used to pay
    /// uint256 purchaseAmount amount user willing to pay
    /// uint256 sizeChanged size of position to open/increase
    /// uint256 collateral amount of collateral token or pay token
    /// bytes extradata some extradata past to hooks, data format described in hook
    function _createIncreasePositionOrder(
        DataTypes.Side _side,
        address _indexToken,
        address _collateralToken,
        DataTypes.OrderType _orderType,
        bytes memory _data
    ) internal returns (uint256 orderId, bool isMarketOrder) {
        DataTypes.LeverageOrder memory order;
        DataTypes.UpdatePositionRequest memory request;
        order.triggerAboveThreshold = _side == DataTypes.Side.SHORT;
        uint256 purchaseAmount;
        bytes memory extradata;
        (order.price, order.payToken, purchaseAmount, request.sizeChange, extradata) =
            abi.decode(_data, (uint256, address, uint256, uint256, bytes));

        if (purchaseAmount == 0) revert ZeroPurchaseAmount();
        if (order.payToken == address(0)) revert InvalidPurchaseToken();

        order.executionFee = order.payToken == ETH ? msg.value - purchaseAmount : msg.value;
        uint256 minExecutionFee = _calcMinLeverageExecutionFee(_collateralToken, order.payToken);
        if (order.executionFee < minExecutionFee) {
            revert ExecutionFeeTooLow();
        }

        isMarketOrder = _orderType == DataTypes.OrderType.MARKET;
        order.owner = msg.sender;
        order.indexToken = _indexToken;
        order.collateralToken = _collateralToken;
        order.expiresAt = isMarketOrder ? block.timestamp + MARKET_ORDER_TIMEOUT : 0;
        order.submissionBlock = block.number;
        order.submissionTimestamp = block.timestamp;
        order.status = DataTypes.OrderStatus.OPEN;

        request.updateType = DataTypes.UpdatePositionType.INCREASE;
        request.side = _side;
        request.collateral = purchaseAmount;

        orderId = nextLeverageOrderId;
        nextLeverageOrderId = orderId + 1;
        leverageOrders[orderId] = order;
        updatePositionRequests[orderId] = request;

        if (order.payToken == ETH) {
            weth.deposit{value: purchaseAmount}();
        } else {
            IERC20(order.payToken).safeTransferFrom(msg.sender, address(this), request.collateral);
        }

        if (address(orderHook) != address(0)) {
            orderHook.postPlaceOrder(orderId, extradata);
        }

        emit LeverageOrderPlaced(orderId, order, request);
    }

    function _poolSwap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _receiver,
        address _beneficier
    ) internal returns (uint256 amountOut) {
        IERC20(_fromToken).safeTransfer(address(pool), _amountIn);
        return _doSwap(_fromToken, _toToken, _minAmountOut, _receiver, _beneficier);
    }

    function _doSwap(
        address _fromToken,
        address _toToken,
        uint256 _minAmountOut,
        address _receiver,
        address _beneficier
    ) internal returns (uint256 amountOut) {
        IERC20 tokenOut = IERC20(_toToken);
        uint256 priorBalance = tokenOut.balanceOf(_receiver);
        pool.swap(_fromToken, _toToken, _minAmountOut, _receiver, abi.encode(_beneficier));
        amountOut = tokenOut.balanceOf(_receiver) - priorBalance;
    }

    function _expiresOrder(uint256 _orderId, DataTypes.LeverageOrder memory _order) internal {
        leverageOrders[_orderId].status = DataTypes.OrderStatus.EXPIRED;
        emit LeverageOrderExpired(_orderId);

        DataTypes.UpdatePositionRequest memory request = updatePositionRequests[_orderId];
        if (request.updateType == DataTypes.UpdatePositionType.INCREASE) {
            _refundCollateral(_order.payToken, request.collateral, _order.owner);
        }
        SafeTransferLib.safeTransferETH(_order.owner, _order.executionFee);
    }

    function _refundCollateral(address _refundToken, uint256 _amount, address _orderOwner) internal {
        if (_refundToken == address(weth) || _refundToken == ETH) {
            _safeUnwrapETH(_amount, _orderOwner);
        } else {
            IERC20(_refundToken).safeTransfer(_orderOwner, _amount);
        }
    }

    function _safeUnwrapETH(uint256 _amount, address _to) internal {
        weth.safeIncreaseAllowance(ETH_UNWRAPPER, _amount);
        IETHUnwrapper(ETH_UNWRAPPER).unwrap(_amount, _to);
    }

    function _validateExecution(address _sender, address _orderOwner, uint256 _submissionTimestamp) internal view {
        if (_sender == address(this)) {
            return;
        }

        if (_sender != executor && (!enablePublicExecution || _sender != _orderOwner)) {
            revert OnlyExecutor();
        }

        if (block.timestamp < _submissionTimestamp + executionDelayTime) {
            revert ExecutionDelay();
        }
    }

    function _calcMinLeverageExecutionFee(address _collateralToken, address _payToken)
        internal
        view
        returns (uint256)
    {
        bool noSwap = _collateralToken == _payToken || (_collateralToken == address(weth) && _payToken == ETH);
        return noSwap ? minLeverageExecutionFee : minLeverageExecutionFee + minSwapExecutionFee;
    }

    function _setMinExecutionFee(uint256 _leverageExecutionFee, uint256 _swapExecutionFee) internal {
        if (_leverageExecutionFee == 0 || _leverageExecutionFee > MAX_MIN_EXECUTION_FEE) {
            revert InvalidExecutionFee();
        }
        if (_swapExecutionFee == 0 || _swapExecutionFee > MAX_MIN_EXECUTION_FEE) {
            revert InvalidExecutionFee();
        }

        minLeverageExecutionFee = _leverageExecutionFee;
        minSwapExecutionFee = _swapExecutionFee;
        emit MinLeverageExecutionFeeSet(_leverageExecutionFee);
        emit MinSwapExecutionFeeSet(_swapExecutionFee);
    }

    function _requireControllerOrOwner() internal view {
        if (msg.sender != owner() && msg.sender != controller) {
            revert OnlyOwnerOrController();
        }
    }

    // ============ Administrative =============

    function setOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) revert ZeroAddress();
        oracle = ILevelOracle(_oracle);
        emit OracleChanged(_oracle);
    }

    function setMinExecutionFee(uint256 _leverageExecutionFee, uint256 _swapExecutionFee) external onlyOwner {
        _setMinExecutionFee(_leverageExecutionFee, _swapExecutionFee);
    }

    function setOrderHook(address _hook) external onlyOwner {
        orderHook = IOrderHook(_hook);
        emit OrderHookSet(_hook);
    }

    function setExecutor(address _executor) external onlyOwner {
        if (_executor == address(0)) revert ZeroAddress();
        executor = _executor;
        emit ExecutorSet(_executor);
    }

    function setController(address _controller) external onlyOwner {
        if (_controller == address(0)) revert ZeroAddress();
        controller = _controller;
        emit ControllerSet(_controller);
    }

    function setEnablePublicExecution(bool _isEnable) external {
        _requireControllerOrOwner();
        enablePublicExecution = _isEnable;
        emit SetEnablePublicExecution(_isEnable);
    }

    function setExecutionDelayTime(uint256 _delay) external {
        _requireControllerOrOwner();
        executionDelayTime = _delay;
        emit SetExecutionDelayTime(_delay);
    }
}

