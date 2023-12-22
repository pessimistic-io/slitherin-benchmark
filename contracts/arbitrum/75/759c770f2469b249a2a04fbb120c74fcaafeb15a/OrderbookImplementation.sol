// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IPool.sol";
import "./IDToken.sol";
import "./ISymbolManager.sol";
import "./IOracleManager.sol";
import "./Admin.sol";
import "./IRouter.sol";
import "./IIsolatedRouter.sol";
import "./RouterImplementation.sol";
import "./RouterStorage.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./OrderbookStorage.sol";
import "./Log.sol";

contract OrderbookImplementation is OrderbookStorage {
    using SafeMath for int256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Log for *;

    event SetExecutor(address executor, bool isActive);
    event CreateOrder(bool indexed isIsolated, address indexed pool, address indexed account, uint256 index, address asset, int256 amount, string symbolName, uint256 executionFee, int256[] orderParams);
    event ExecuteOrder(bool indexed isIsolated, address indexed pool, address indexed account, uint256 index, address asset, int256 amount, string symbolName, uint256 executionFee, int256[] orderParams);
    event CancelOrder(bool indexed isIsolated, address indexed pool, address indexed account, uint256 index, address asset, int256 amount, string symbolName, uint256 executionFee, int256[] orderParams);


    function setRouter(address _pool, address _router) external _onlyAdmin_ {
        routers[_pool] = _router;
    }

    function setIsolatedRouter(address _router) external _onlyAdmin_ {
        isolatedRouter = _router;
    }

    function setExecutor(address executor, bool isActive) external _onlyAdmin_ {
        isExecutor[executor] = isActive;
        emit SetExecutor(executor, isActive);
    }

    function createOrder(bool isIsolated, address pool, string calldata symbolName, address asset, int256 amount, int256[] calldata orderParams) external payable {
        address account = msg.sender;
        uint256 executionFee_;
        if (amount > 0 && asset == address(0)) {
            require(
                msg.value >= amount.itou(),
                "orderbook: insufficient ETH amount"
            );
            executionFee_ = msg.value - amount.itou();
        } else {
            executionFee_ = msg.value;
        }
        if (isIsolated) {
            uint256 executionFee = IIsolatedRouter(isolatedRouter).executionFee();
            require(
                executionFee_ >= executionFee,
                "orderbook: insufficient executionFee"
            );
        } else {
            uint256 executionFee = IRouter(routers[pool]).executionFee();
            require(
                executionFee_ >= executionFee,
                "orderbook: insufficient executionFee"
            );
        }

        uint256 orderIndex = ++ordersIndex[account];
        orders[account][orderIndex] = Order(
            isIsolated,
            pool,
            account,
            orderIndex,
            asset,
            amount,
            symbolName,
            executionFee_,
            orderParams
        );
        emit CreateOrder(isIsolated, pool, account, orderIndex, asset, amount, symbolName, executionFee_, orderParams);
    }


    function executeOrder(address account, uint256 index) external payable {
        address executor = msg.sender;
        require(isExecutor[executor], "Orderbook: executor only");

        Order memory order = orders[account][index];
        require(order.account != address(0), "Orderbook: non-existent order");
        int256[] memory tradeParams = new int256[](2);
        // Copy the volume and priceLimit into tradeParams
        tradeParams[0] = order.orderParams[3]; // volume
        tradeParams[1] = order.orderParams[4]; // priceLimit

        if (order.isIsolated) {
            uint256 val = IIsolatedRouter(isolatedRouter).executionFee();
            if (order.asset == address(0) && order.amount > 0) {
                val += order.amount.itou();
            }
            IIsolatedRouter(isolatedRouter).requestDelegateTrade{value:val}(
                order.pool,
                order.account,
                order.asset,
                order.amount,
                order.symbolName,
                tradeParams
            );
        } else {
            uint256 val = IRouter(routers[order.pool]).executionFee();
            IRouter(routers[order.pool]).requestDelegateTrade{value:val}(
                order.account,
                order.symbolName,
                tradeParams
            );
        }

        delete orders[account][index];
        emit ExecuteOrder(order.isIsolated, order.pool, account, index, order.asset, order.amount, order.symbolName, order.executionFee, order.orderParams);

    }


    function cancelOrder(address account, uint256 index) external _reentryLock_ {
        require(msg.sender == account, "orderbook: not order owner");
        require(orders[account][index].account != address(0), "orderbook: non-existent order");

        Order memory order = orders[account][index];
        delete orders[account][index];

        if (order.amount > 0 && order.asset == address(0)) {
            payable(account).transfer(order.amount.itou() + order.executionFee);
        } else if (order.amount > 0 && order.asset != address(0)) {
            IERC20(order.asset).safeTransfer(account, order.amount.itou());
            payable(account).transfer(order.executionFee);
        } else {
            payable(account).transfer(order.executionFee);
        }

        emit CancelOrder(order.isIsolated, order.pool, account, index, order.asset, order.amount, order.symbolName, order.executionFee, order.orderParams);
    }

}

