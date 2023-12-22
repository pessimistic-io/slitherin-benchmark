// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IPool, Side} from "./IPool.sol";
import {SwapOrder, Order} from "./IOrderManager.sol";
import {IOracle} from "./IOracle.sol";
import {IWETH} from "./IWETH.sol";
import {IETHUnwrapper} from "./IETHUnwrapper.sol";
import {IOrderHook} from "./IOrderHook.sol";
import {IPermit} from "./IPermit.sol";

// since we defined this function via a state variable of PoolStorage, it cannot be re-declared the interface IPool
interface IWhitelistedPool is IPool {
    function isListed(address) external returns (bool);
    function allTranches(uint256 index) external returns (address);
}

enum UpdatePositionType {
    INCREASE,
    DECREASE
}

enum OrderType {
    MARKET,
    LIMIT
}

struct UpdatePositionRequest {
    Side side;
    uint256 sizeChange;
    uint256 collateral;
    UpdatePositionType updateType;
}

interface IFarm {
  function depositFor(uint256, uint256, address) external;
  function withdrawFrom(uint256, uint256, address) external;
}

interface ILPToken {
  function minter() external returns (address);
}

contract OrderManager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    uint256 constant MARKET_ORDER_TIMEOUT = 5 minutes;
    uint256 constant MAX_MIN_EXECUTION_FEE = 1e17; // 0.1 ETH
    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IWETH public weth;

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => UpdatePositionRequest) public requests;

    uint256 public nextSwapOrderId;
    mapping(uint256 => SwapOrder) public swapOrders;

    IWhitelistedPool public mainPool;
    IOracle public oracle;
    uint256 public minExecutionFee;

    IOrderHook public orderHook;

    mapping(address => uint256[]) public userOrders;
    mapping(address => uint256[]) public userSwapOrders;

    IETHUnwrapper public ethUnwrapper;

    address public executor;

    IFarm public farm;
    mapping(address => IWhitelistedPool) public tranchePools;
    mapping(address => bool) public poolStatus;
    mapping(address => uint256 ) public trancheFarmPid;

    modifier onlyExecutor() {
        _validateExecutor(msg.sender);
        _;
    }

    receive() external payable {
        // prevent send ETH directly to contract
        require(msg.sender == address(weth), "OrderManager:rejected");
    }

    function initialize(address _weth, address _oracle, uint256 _minExecutionFee, address _ethUnwrapper)
        external
        initializer
    {
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        require(_oracle != address(0), "OrderManager:invalidOracle");
        require(_weth != address(0), "OrderManager:invalidWeth");
        require(_minExecutionFee <= MAX_MIN_EXECUTION_FEE, "OrderManager:minExecutionFeeTooHigh");
        require(_ethUnwrapper != address(0), "OrderManager:invalidEthUnwrapper");
        minExecutionFee = _minExecutionFee;
        oracle = IOracle(_oracle);
        nextOrderId = 1;
        nextSwapOrderId = 1;
        weth = IWETH(_weth);
        ethUnwrapper = IETHUnwrapper(_ethUnwrapper);
    }

    // ============= VIEW FUNCTIONS ==============
    function getOrders(address user, uint256 skip, uint256 take)
        external
        view
        returns (uint256[] memory orderIds, uint256 total)
    {
        total = userOrders[user].length;
        uint256 toIdx = skip + take;
        toIdx = toIdx > total ? total : toIdx;
        uint256 nOrders = toIdx > skip ? toIdx - skip : 0;
        orderIds = new uint[](nOrders);
        for (uint256 i = 0; i < nOrders; i++) {
            orderIds[i] = userOrders[user][i];
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
        for (uint256 i = 0; i < nOrders; i++) {
            orderIds[i] = userSwapOrders[user][i];
        }
    }

    // =========== MUTATIVE FUNCTIONS ==========
    function placeOrder(
        IERC20 _tranche,
        UpdatePositionType _updateType,
        Side _side,
        address _indexToken,
        address _collateralToken,
        OrderType _orderType,
        bytes calldata data
    ) public payable nonReentrant {
        IWhitelistedPool pool = getPool(_tranche);
        bool isIncrease = _updateType == UpdatePositionType.INCREASE;
        require(pool.validateToken(_indexToken, _collateralToken, _side, isIncrease), "OrderManager:invalidTokens");
        uint256 orderId;
        if (isIncrease) {
            orderId = _createIncreasePositionOrder2(pool, _tranche, _side, _indexToken, _collateralToken, _orderType, data);
        } else {
            orderId = _createDecreasePositionOrder(pool, _side, _indexToken, _collateralToken, _orderType, data);
        }
        userOrders[msg.sender].push(orderId);
    }

    function placeOrderWithPermit(
        IERC20 _tranche,
        UpdatePositionType _updateType,
        Side _side,
        address _indexToken,
        address _collateralToken,
        OrderType _orderType,
        bytes calldata data,
        address _token, uint256[] memory _rvs, bytes32 r, bytes32 s
    ) external payable {
        // uint256 deadline, uint256 value, uint8 v
        IPermit(_token).permit(msg.sender, address(this), _rvs[1], _rvs[0], uint8(_rvs[2]), r, s);
        placeOrder(_tranche, _updateType, _side, _indexToken, _collateralToken, _orderType, data);
    }

    function placeSwapOrder(IERC20 _tranche, address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _minOut, uint256 _price)
        external
        payable
        nonReentrant
    {
        IWhitelistedPool pool = getPool(_tranche);
        address payToken;
        (payToken, _tokenIn) = _tokenIn == ETH ? (ETH, address(weth)) : (_tokenIn, _tokenIn);
        // if token out is ETH, check wether pool support WETH
        require(
            pool.isListed(_tokenIn) && pool.isListed(_tokenOut == ETH ? address(weth) : _tokenOut),
            "OrderManager:invalidTokens"
        );

        uint256 executionFee;
        if (payToken == ETH) {
            executionFee = msg.value - _amountIn;
            weth.deposit{value: _amountIn}();
        } else {
            executionFee = msg.value;
            IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
        }

        require(executionFee >= minExecutionFee, "OrderManager:executionFeeTooLow");

        SwapOrder memory order = SwapOrder({
            pool: pool,
            owner: msg.sender,
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            amountIn: _amountIn,
            minAmountOut: _minOut,
            price: _price,
            executionFee: executionFee
        });
        swapOrders[nextSwapOrderId] = order;
        userSwapOrders[msg.sender].push(nextSwapOrderId);
        emit SwapOrderPlaced(nextSwapOrderId);
        nextSwapOrderId += 1;
    }

	function swap(uint256 _amountIn, uint256 _minAmountOut, address[] memory _path) public payable {
        require(_path.length >= 3, "invalide path length");
        uint256 amountOut = _poolSwap2(_path, _amountIn, _minAmountOut, msg.sender, msg.sender);
        emit Swap(msg.sender, _path[0], _path[_path.length - 1], address(0), _amountIn, amountOut);
	}

	function swapWithPermit(uint256 _amountIn, uint256 _minAmountOut, address[] memory _path,
         uint256 deadline, uint256 value, uint8 v, bytes32 r, bytes32 s)
         external payable {
        IPermit(address(_path[0])).permit(msg.sender, address(this), value, deadline, v, r, s);
        swap(_amountIn, _minAmountOut, _path);
	}

    function executeOrder(uint256 _orderId, address payable _feeTo) external nonReentrant onlyExecutor {
        Order memory order = orders[_orderId];
        require(order.owner != address(0), "OrderManager:orderNotExists");
        require(block.number > order.submissionBlock, "OrderManager:blockNotPass");
        _validatePool(order.pool);

        if (order.expiresAt != 0 && order.expiresAt < block.timestamp) {
            _expiresOrder(_orderId, order);
            return;
        }

        UpdatePositionRequest memory request = requests[_orderId];
        uint256 indexPrice = _getMarkPrice(order, request);
        bool isValid = order.triggerAboveThreshold ? indexPrice >= order.price : indexPrice <= order.price;
        if (!isValid) {
            require(order.expiresAt != 0, "OrderManager:invalidLimitOrderPrice");
            return;
        }

        _executeRequest(order, request);
        delete orders[_orderId];
        delete requests[_orderId];
        _safeTransferETH(_feeTo, order.executionFee);
        emit OrderExecuted(_orderId, order, request, indexPrice);
    }

    function _getMarkPrice(Order memory order, UpdatePositionRequest memory request) internal view returns (uint256) {
        bool max = (request.updateType == UpdatePositionType.INCREASE) == (request.side == Side.LONG);
        return oracle.getPrice(order.indexToken, max);
    }

    function cancelOrder(uint256 _orderId) external nonReentrant {
        Order memory order = orders[_orderId];
        require(order.owner == msg.sender, "OrderManager:unauthorizedCancellation");
        UpdatePositionRequest memory request = requests[_orderId];

        delete orders[_orderId];
        delete requests[_orderId];

        _safeTransferETH(order.owner, order.executionFee);
        if (request.updateType == UpdatePositionType.INCREASE) {
            _refundCollateral(order.collateralToken, request.collateral, order.owner);
        }

        emit OrderCancelled(_orderId);
    }

    function cancelSwapOrder(uint256 _orderId) external nonReentrant {
        SwapOrder memory order = swapOrders[_orderId];
        require(order.owner == msg.sender, "OrderManager:unauthorizedCancellation");
        delete swapOrders[_orderId];
        _safeTransferETH(order.owner, order.executionFee);
        IERC20(order.tokenIn).safeTransfer(order.owner, order.amountIn);
        emit SwapOrderCancelled(_orderId);
    }

    function executeSwapOrder(uint256 _orderId, address payable _feeTo) external nonReentrant onlyExecutor {
        SwapOrder memory order = swapOrders[_orderId];
        IPool pool = order.pool;
        _validatePool(pool);
        require(order.owner != address(0), "OrderManager:notFound");
        delete swapOrders[_orderId];
        IERC20(order.tokenIn).safeTransfer(address(pool), order.amountIn);
        uint256 amountOut;
        if (order.tokenOut != ETH) {
            amountOut = _doSwap(pool, order.tokenIn, order.tokenOut, order.minAmountOut, order.owner, order.owner);
        } else {
            amountOut = _doSwap(pool, order.tokenIn, address(weth), order.minAmountOut, address(this), order.owner);
            _safeUnwrapETH(amountOut, order.owner);
        }
        _safeTransferETH(_feeTo, order.executionFee);
        require(amountOut >= order.minAmountOut, "OrderManager:slippageReached");
        emit SwapOrderExecuted(_orderId, order.amountIn, amountOut);
    }

    function _executeRequest(Order memory _order, UpdatePositionRequest memory _request) internal {
        if (_request.updateType == UpdatePositionType.INCREASE) {
            IERC20(_order.collateralToken).safeTransfer(address(_order.pool), _request.collateral);
            _order.pool.increasePosition(
                _order.owner, _order.indexToken, _order.collateralToken, _request.sizeChange, _request.side
            );
        } else {
            IERC20 collateralToken = IERC20(_order.collateralToken);
            uint256 priorBalance = collateralToken.balanceOf(address(this));
            _order.pool.decreasePosition(
                _order.owner,
                _order.indexToken,
                _order.collateralToken,
                _request.collateral,
                _request.sizeChange,
                _request.side,
                address(this)
            );
            uint256 payoutAmount = collateralToken.balanceOf(address(this)) - priorBalance;

            address _tranche = IWhitelistedPool(address(_order.pool)).allTranches(0);
            address[] memory payPath = new address[](3);
            payPath[0] = _order.collateralToken;
            payPath[1] = _tranche;
            payPath[2] = _order.payToken;
            // min amount out
            uint256 amountOut = __poolSwap(payPath, payoutAmount, 0, _order.owner);

            if (_order.payToken == ETH) {
                _safeUnwrapETH(amountOut, _order.owner);
            } else {
                IERC20(_order.payToken).safeTransfer(_order.owner, amountOut);
            }
        }
    }

    function _createDecreasePositionOrder(
        IWhitelistedPool _pool,
        Side _side,
        address _indexToken,
        address _collateralToken,
        OrderType _orderType,
        bytes memory _data
    ) internal returns (uint256 orderId) {
        Order memory order;
        UpdatePositionRequest memory request;
        bytes memory extradata;

        if (_orderType == OrderType.MARKET) {
            (order.price, order.payToken, request.sizeChange, request.collateral, extradata) =
                abi.decode(_data, (uint256, address, uint256, uint256, bytes));
            order.triggerAboveThreshold = _side == Side.LONG;
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
        order.pool = _pool;
        order.owner = msg.sender;
        order.indexToken = _indexToken;
        order.collateralToken = _collateralToken;
        order.expiresAt = _orderType == OrderType.MARKET ? block.timestamp + MARKET_ORDER_TIMEOUT : 0;
        order.submissionBlock = block.number;
        order.executionFee = msg.value;
        require(order.executionFee >= minExecutionFee, "OrderManager:executionFeeTooLow");

        request.updateType = UpdatePositionType.DECREASE;
        request.side = _side;
        orderId = nextOrderId;
        nextOrderId = orderId + 1;
        orders[orderId] = order;
        requests[orderId] = request;

        if (address(orderHook) != address(0)) {
            orderHook.postPlaceOrder(orderId, extradata);
        }

        emit OrderPlaced(orderId, order, request);
    }

    function _createIncreasePositionOrder2(
        IWhitelistedPool _pool,
        IERC20 _tranche,
        Side _side,
        address _indexToken,
        address _collateralToken,
        OrderType _orderType,
        bytes memory _data
    ) internal returns (uint256 orderId) {
        Order memory order;
        UpdatePositionRequest memory request;
        order.triggerAboveThreshold = _side == Side.SHORT;
        address purchaseToken;
        uint256 purchaseAmount;
        bytes memory extradata;
        address[] memory purchasePath;
        (order.price, purchaseToken, purchaseAmount, purchasePath, request.sizeChange, request.collateral, extradata) =
            abi.decode(_data, (uint256, address, uint256, address[], uint256, uint256, bytes));

        //require(purchaseAmount != 0, "OrderManager:invalidPurchaseAmount");
        require(purchaseToken != address(0), "OrderManager:invalidPurchaseToken");

        order.pool = _pool;
        order.owner = msg.sender;
        order.indexToken = _indexToken;
        order.collateralToken = _collateralToken;
        order.expiresAt = _orderType == OrderType.MARKET ? block.timestamp + MARKET_ORDER_TIMEOUT : 0;
        order.submissionBlock = block.number;
        //order.executionFee = purchaseToken == ETH ? msg.value - purchaseAmount : msg.value;
        //require(order.executionFee >= minExecutionFee, "OrderManager:executionFeeTooLow");
        request.updateType = UpdatePositionType.INCREASE;
        request.side = _side;
        orderId = nextOrderId;
        nextOrderId = orderId + 1;
        requests[orderId] = request;

        if (purchasePath.length == 0) {
            purchasePath = new address[](3);
            purchasePath[0] = purchaseToken;
            purchasePath[1] = address(_tranche);
            purchasePath[2] = _collateralToken;
        } else {
            if (purchaseToken == ETH) {
                require(purchasePath[0] == purchaseToken || purchasePath[0] == address(weth), "purchase token invalid");
            } else {
                require(purchasePath[0] == purchaseToken, "purchase token invalid");
            }
            require(purchasePath[purchasePath.length - 1] == _collateralToken, "collateral token invalid");
        }

        if (purchaseToken == ETH) {
            if (purchaseAmount > 0) {
                weth.safeTransferFrom(msg.sender, address(this), purchaseAmount);
            }
            require(msg.value >= minExecutionFee, "OrderManager:executionFeeTooLow ether");
            order.executionFee = minExecutionFee;
            if (msg.value > minExecutionFee) {
                weth.deposit{value: msg.value - minExecutionFee}();
                purchaseAmount += (msg.value - minExecutionFee);
            }
            purchaseToken = address(weth);
        } else {
            order.executionFee = msg.value;
            IERC20(purchaseToken).safeTransferFrom(msg.sender, address(this), purchaseAmount);
        }
        require(purchaseAmount != 0, "OrderManager:invalidPurchaseAmount");
        require(order.executionFee >= minExecutionFee, "OrderManager:executionFeeTooLow");

        if (purchaseToken != _collateralToken) {
            // update request collateral value to the actual swap output
            requests[orderId].collateral = __poolSwap(purchasePath, purchaseAmount, request.collateral, order.owner);
        } else {
            require(purchaseAmount == request.collateral, "OrderManager:invalidPurchaseAmount");
        }

        if (address(orderHook) != address(0)) {
            orderHook.postPlaceOrder(orderId, extradata);
        }

        orders[orderId] = order;

        emit OrderPlaced(orderId, order, request);
    }


    function _poolSwap(
        IWhitelistedPool _pool,
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _receiver,
        address _beneficier
    ) internal returns (uint256 amountOut) {
        address payToken;
        (payToken, _fromToken) = _fromToken == ETH ? (ETH, address(weth)) : (_fromToken, _fromToken);
        if (payToken == ETH) {
            weth.deposit{value: _amountIn}();
            weth.safeTransfer(address(_pool), _amountIn);
        } else {
            IERC20(_fromToken).safeTransferFrom(msg.sender, address(_pool), _amountIn);
        }
        return _doSwap(_pool, _fromToken, _toToken, _minAmountOut, _receiver, _beneficier);
    }

    function _doSwap(
        IPool _pool,
        address _fromToken,
        address _toToken,
        uint256 _minAmountOut,
        address _receiver,
        address _beneficier
    ) internal returns (uint256 amountOut) {
        IERC20 tokenOut = IERC20(_toToken);
        uint256 priorBalance = tokenOut.balanceOf(_receiver);
        _pool.swap(_fromToken, _toToken, _minAmountOut, _receiver, abi.encode(_beneficier));
        amountOut = tokenOut.balanceOf(_receiver) - priorBalance;
    }

    function _expiresOrder(uint256 _orderId, Order memory _order) internal {
        UpdatePositionRequest memory request = requests[_orderId];
        delete orders[_orderId];
        delete requests[_orderId];
        emit OrderExpired(_orderId);

        _safeTransferETH(_order.owner, _order.executionFee);
        if (request.updateType == UpdatePositionType.INCREASE) {
            _refundCollateral(_order.collateralToken, request.collateral, _order.owner);
        }
    }

    function _refundCollateral(address _collateralToken, uint256 _amount, address _orderOwner) internal {
        if (_collateralToken == address(weth)) {
            _safeUnwrapETH(_amount, _orderOwner);
        } else {
            IERC20(_collateralToken).safeTransfer(_orderOwner, _amount);
        }
    }

    function _safeTransferETH(address _to, uint256 _amount) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = _to.call{value: _amount}(new bytes(0));
        require(success, "TransferHelper: ETH_TRANSFER_FAILED");
    }

    function _safeUnwrapETH(uint256 _amount, address _to) internal {
        weth.safeIncreaseAllowance(address(ethUnwrapper), _amount);
        ethUnwrapper.unwrap(_amount, _to);
    }

    function _validateExecutor(address _sender) internal view {
        require(_sender == executor, "OrderManager:onlyExecutor");
    }
    function _validateTranche(IERC20 _tranche) internal view {
        require(address(tranchePools[address(_tranche)]) != address(0), "OrderManager:validateTranche");
    }
    function _validatePool(IPool _pool) internal view {
        require(poolStatus[address(_pool)], "OrderManager:validatePool");
    }
    function getPool(IERC20 _tranche) public view returns (IWhitelistedPool pool) {
        pool = tranchePools[address(_tranche)];
        _validateTranche(_tranche);
        _validatePool(pool);
    }

    // ============ New API ===========

	// token0,tranche0,token1
	// token0,tranche0,token1,tranche1,token2
    function _poolSwap2(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _receiver,
        address _beneficier
    ) internal returns (uint256 amountOut) {
        require(_path.length >= 3, "invalide path length");

        address fromToken = _path[0];
        address toToken = _path[_path.length - 1];
        if (fromToken == ETH) {
            if (_amountIn > 0) {
                weth.safeTransferFrom(msg.sender, address(this), _amountIn);
            }
            if (msg.value > 0) {
                weth.deposit{value: msg.value}();
                _amountIn += msg.value;
            }
        } else {
            IERC20(fromToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        }

        amountOut = __poolSwap(_path, _amountIn, _minAmountOut, _beneficier);

        if (toToken == ETH) {
            _safeUnwrapETH(amountOut, _receiver);
        } else {
            IERC20(toToken).safeTransfer(_receiver, amountOut);
        }
    }

    function __poolSwap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _beneficier
    ) internal returns (uint256) {
        uint len = (_path.length - 1) / 2;
        for(uint i = 0; i < len; ) {
            address fromToken = _path[2 * i];
            address tranche = _path[2 * i + 1];
            address toToken = _path[2 * i + 2];
            if (fromToken == ETH) fromToken = address(weth);
            if (toToken == ETH) toToken = address(weth);
            if (fromToken != toToken) {
                IPool pool = getPool(IERC20(tranche));
                IERC20(fromToken).safeTransfer(address(pool), _amountIn);
                _amountIn = _doSwap(pool, fromToken, toToken, 0, address(this), _beneficier);
            }
            unchecked {
                i = i + 1;
            }
        }

        require(_amountIn >= _minAmountOut, "!min amount out");
        return _amountIn;
    }

    // ============ Stake & Unstake ============

    function addLiquidity(IERC20 _tranche, IERC20 _token, uint256 _amountIn, uint256 _minLpAmount, bool _stake)
        public payable
    {
        _token.safeTransferFrom(msg.sender, address(this), _amountIn);
        if (address(_token) == address(weth) && msg.value > 0) {
            weth.deposit{value: msg.value}();
            _amountIn += msg.value;
        }

        _addLiquidity(_tranche, _token, _amountIn, _minLpAmount, _stake);
    }
    function addLiquidityWithPermit(IERC20 _tranche, IERC20 _token, uint256 _amountIn, uint256 _minLpAmount, bool _stake,
        uint256 deadline, uint256 value, uint8 v, bytes32 r, bytes32 s)
        external payable
    {
        IPermit(address(_token)).permit(msg.sender, address(this), value, deadline, v, r, s);
        addLiquidity(_tranche, _token, _amountIn, _minLpAmount, _stake);
    }

    function _addLiquidity(IERC20 _tranche, IERC20 _token, uint256 _amountIn, uint256 _minLpAmount, bool _stake) internal {
        IWhitelistedPool pool = getPool(_tranche);
        require(pool.isListed(address(_token)), "OrderManager:invalidStakeTokens");
        _token.safeApprove(address(pool), _amountIn);
        if (_stake) {
            uint256 lpAmount = _tranche.balanceOf(address(this));
            pool.addLiquidity(address(_tranche), address(_token), _amountIn, _minLpAmount, address(this));
            lpAmount = _tranche.balanceOf(address(this)) - lpAmount;

            // stake to farm
            _tranche.safeApprove(address(farm), lpAmount);
            farm.depositFor(trancheFarmPid[address(_tranche)], lpAmount, msg.sender);
        } else {
            pool.addLiquidity(address(_tranche), address(_token), _amountIn, _minLpAmount, msg.sender);
        }
    }

    function removeLiquidity(IERC20 _tranche, uint256 _lpAmount, address _tokenOut, uint256 _minOut, bool _unstake, bool _native)
        external
    {
        IWhitelistedPool pool = getPool(_tranche);
        if (_unstake) {
            farm.withdrawFrom(trancheFarmPid[address(_tranche)], _lpAmount, msg.sender);
        } else {
            _tranche.safeTransferFrom(msg.sender, address(this), _lpAmount);
        }

        _tranche.safeApprove(address(pool), _lpAmount);
        if (_native) {
            uint256 amountOut = weth.balanceOf(address(this));
            pool.removeLiquidity(address(_tranche), address(weth), _lpAmount, _minOut, address(this));
            amountOut = weth.balanceOf(address(this)) - amountOut;
            _safeUnwrapETH(amountOut, msg.sender);
        } else {
            pool.removeLiquidity(address(_tranche), _tokenOut, _lpAmount, _minOut, msg.sender);
        }
    }

    // ============ Administrative =============

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "OrderManager:invalidOracleAddress");
        oracle = IOracle(_oracle);
        emit OracleChanged(_oracle);
    }

    function setFarm(address _farm) external onlyOwner {
        require(_farm != address(0), "OrderManager:invalidFarmAddress");
        require(address(farm) != _farm, "OrderManager:faramAlreadyAdded");
        farm = IFarm(_farm);
        emit FarmSet(_farm);
    }
    function setTrancheFarmPid(address _tranche, uint256 _pid) external onlyOwner {
        trancheFarmPid[_tranche] = _pid;
    }
    function setTranchePool(address _tranche, IWhitelistedPool _pool) external onlyOwner {
        tranchePools[_tranche] = _pool;
        poolStatus[address(_pool)] = true;
    }
    function addTranche(address _tranche) external onlyOwner {
        IWhitelistedPool pool = IWhitelistedPool(ILPToken(_tranche).minter());
        tranchePools[_tranche] = pool;
        poolStatus[address(pool)] = true;
    }

    function setMinExecutionFee(uint256 _fee) external onlyOwner {
        require(_fee != 0, "OrderManager:invalidFeeValue");
        require(_fee <= MAX_MIN_EXECUTION_FEE, "OrderManager:minExecutionFeeTooHigh");
        minExecutionFee = _fee;
        emit MinExecutionFeeSet(_fee);
    }

    function setOrderHook(address _hook) external onlyOwner {
        orderHook = IOrderHook(_hook);
        emit OrderHookSet(_hook);
    }

    function setExecutor(address _executor) external onlyOwner {
        require(_executor != address(0), "OrderManager:invalidAddress");
        executor = _executor;
        emit ExecutorSet(_executor);
    }

    // ========== EVENTS =========

    event OrderPlaced(uint256 indexed key, Order order, UpdatePositionRequest request);
    event OrderCancelled(uint256 indexed key);
    event OrderExecuted(uint256 indexed key, Order order, UpdatePositionRequest request, uint256 fillPrice);
    event OrderExpired(uint256 indexed key);
    event OracleChanged(address);
    event SwapOrderPlaced(uint256 indexed key);
    event SwapOrderCancelled(uint256 indexed key);
    event SwapOrderExecuted(uint256 indexed key, uint256 amountIn, uint256 amountOut);
    event Swap(
        address indexed account,
        address indexed tokenIn,
        address indexed tokenOut,
        address pool,
        uint256 amountIn,
        uint256 amountOut
    );
    event PoolSet(address indexed pool);
    event FarmSet(address indexed farm);
    event MinExecutionFeeSet(uint256 fee);
    event OrderHookSet(address indexed hook);
    event ExecutorSet(address indexed executor);
}

