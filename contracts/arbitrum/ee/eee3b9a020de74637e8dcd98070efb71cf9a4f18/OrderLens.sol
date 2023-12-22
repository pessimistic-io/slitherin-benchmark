pragma solidity 0.8.18;

import {IOrderManagerWithStorage} from "./IOrderManagerWithStorage.sol";
import {IPoolWithStorage} from "./IPoolWithStorage.sol";
import {ILiquidityCalculator} from "./ILiquidityCalculator.sol";
import {PositionLogic} from "./PositionLogic.sol";
import {DataTypes} from "./DataTypes.sol";
import {Constants} from "./Constants.sol";

contract OrderLens {
    struct LeverageOrderView {
        uint256 id;
        address indexToken;
        address collateralToken;
        address payToken;
        DataTypes.Side side;
        DataTypes.UpdatePositionType updateType;
        uint256 triggerPrice;
        uint256 sizeChange;
        uint256 collateral;
        uint256 expiresAt;
        bool triggerAboveThreshold;
    }

    struct SwapOrderView {
        uint256 id;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 price;
    }

    IOrderManagerWithStorage public immutable orderManager;
    IPoolWithStorage public immutable pool;

    constructor(address _orderManager, address _pool) {
        require(_orderManager != address(0), "invalid address");
        require(_pool != address(0), "invalid address");
        orderManager = IOrderManagerWithStorage(_orderManager);
        pool = IPoolWithStorage(_pool);
    }

    function getOpenLeverageOrders(address _owner, uint256 _skip, uint256 _take, uint256 _head)
        external
        view
        returns (LeverageOrderView[] memory, uint256)
    {
        uint256 totalOrder = orderManager.userLeverageOrderCount(_owner);

        uint256 remain = totalOrder > _head ? totalOrder - _head : 0;
        if (remain == 0 || _skip >= totalOrder) {
            return (new LeverageOrderView[](0), remain);
        }

        uint256 startIndex = totalOrder - _skip;

        LeverageOrderView[] memory openOrders = new LeverageOrderView[](_take);
        uint256 count = 0;

        for (uint256 i = startIndex; i > _head && count < _take; --i) {
            uint256 orderId = orderManager.userLeverageOrders(_owner, i - 1);
            LeverageOrderView memory order = _parseLeverageOrder(orderId);
            if (order.indexToken != address(0)) {
                openOrders[count] = order;
                count++;
            }
        }

        if (count == _take) {
            return (openOrders, remain);
        }
        // trim empty item
        LeverageOrderView[] memory ret = new LeverageOrderView[](count);
        for (uint256 i = 0; i < count; i++) {
            ret[i] = openOrders[i];
        }

        return (ret, remain);
    }

    /// @param _head number of elements to skip from head
    function getOpenSwapOrders(address _owner, uint256 _skip, uint256 _take, uint256 _head)
        external
        view
        returns (SwapOrderView[] memory, uint256 remain)
    {
        uint256 totalOrder = orderManager.userSwapOrderCount(_owner);
        remain = totalOrder > _head ? totalOrder - _head : 0;
        if (remain == 0 || _skip >= totalOrder) {
            return (new SwapOrderView[](0), remain);
        }

        uint256 startIndex = totalOrder - _skip;
        SwapOrderView[] memory openOrders = new SwapOrderView[](_take);
        uint256 count = 0;

        for (uint256 i = startIndex; i > _head && count < _take; --i) {
            uint256 orderId = orderManager.userSwapOrders(_owner, i - 1);
            SwapOrderView memory order = _parseSwapOrder(orderId);
            if (order.tokenIn != address(0)) {
                openOrders[count] = order;
                count++;
            }
        }

        if (count == _take) {
            return (openOrders, remain);
        }
        // trim empty item
        SwapOrderView[] memory ret = new SwapOrderView[](count);
        for (uint256 i = 0; i < count; i++) {
            ret[i] = openOrders[i];
        }

        return (ret, remain);
    }

    function canExecuteLeverageOrders(uint256[] calldata _orderIds) external view returns (bool[] memory) {
        uint256 count = _orderIds.length;
        bool[] memory rejected = new bool[](count);
        uint256 positionFee = pool.positionFee();
        uint256 liquidationFee = pool.liquidationFee();
        for (uint256 i = 0; i < count; ++i) {
            uint256 orderId = _orderIds[i];
            DataTypes.LeverageOrder memory order = orderManager.leverageOrders(orderId);
            if (order.status != DataTypes.OrderStatus.OPEN) {
                rejected[i] = true;
                continue;
            }

            if (order.expiresAt != 0 && order.expiresAt < block.timestamp) {
                continue;
            }

            DataTypes.UpdatePositionRequest memory request = orderManager.updatePositionRequests(orderId);
            DataTypes.Position memory position = pool.positions(
                PositionLogic.getPositionKey(order.owner, order.indexToken, order.collateralToken, request.side)
            );

            if (request.updateType == DataTypes.UpdatePositionType.DECREASE) {
                if (position.size == 0) {
                    rejected[i] = true;
                    continue;
                }

                if (request.sizeChange < position.size) {
                    // partial close
                    if (position.collateralValue < request.collateral) {
                        rejected[i] = true;
                        continue;
                    }

                    uint256 newSize = position.size - request.sizeChange;
                    uint256 fee = positionFee * request.sizeChange / Constants.PRECISION;
                    uint256 newCollateral = position.collateralValue - request.collateral;
                    newCollateral = newCollateral > fee ? newCollateral - fee : 0;
                    rejected[i] = newCollateral < liquidationFee || newCollateral > newSize; // leverage
                    continue;
                }
            }
        }

        return rejected;
    }

    function canExecuteSwapOrders(uint256[] calldata _orderIds) external view returns (bool[] memory rejected) {
        uint256 count = _orderIds.length;
        rejected = new bool[](count);

        for (uint256 i = 0; i < count; ++i) {
            uint256 orderId = _orderIds[i];
            DataTypes.SwapOrder memory order = orderManager.swapOrders(orderId);
            if (order.status != DataTypes.OrderStatus.OPEN) {
                rejected[i] = true;
                continue;
            }

            ILiquidityCalculator liquidityCalculator = pool.liquidityCalculator();
            (uint256 amountOut,,,) = liquidityCalculator.calcSwapOutput(order.tokenIn, order.tokenOut, order.amountIn);
            rejected[i] = amountOut < order.minAmountOut;
        }
    }

    function _parseLeverageOrder(uint256 _id) private view returns (LeverageOrderView memory leverageOrder) {
        DataTypes.LeverageOrder memory order = orderManager.leverageOrders(_id);
        if (order.status == DataTypes.OrderStatus.OPEN) {
            DataTypes.UpdatePositionRequest memory request = orderManager.updatePositionRequests(_id);
            leverageOrder.id = _id;
            leverageOrder.indexToken = order.indexToken;
            leverageOrder.collateralToken = order.collateralToken;
            leverageOrder.payToken = order.payToken != address(0) ? order.payToken : order.collateralToken;
            leverageOrder.triggerPrice = order.price;
            leverageOrder.triggerAboveThreshold = order.triggerAboveThreshold;
            leverageOrder.expiresAt = order.expiresAt;
            leverageOrder.side = request.side;
            leverageOrder.updateType = request.updateType;
            leverageOrder.sizeChange = request.sizeChange;
            leverageOrder.collateral = request.collateral;
        }
    }

    function _parseSwapOrder(uint256 _id) private view returns (SwapOrderView memory swapOrder) {
        DataTypes.SwapOrder memory order = orderManager.swapOrders(_id);

        if (order.status == DataTypes.OrderStatus.OPEN) {
            swapOrder.id = _id;
            swapOrder.tokenIn = order.tokenIn;
            swapOrder.tokenOut = order.tokenOut;
            swapOrder.amountIn = order.amountIn;
            swapOrder.minAmountOut = order.minAmountOut;
            swapOrder.price = order.price;
        }
    }
}

