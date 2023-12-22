// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "./SafeERC20Upgradeable.sol";
import "./LibSubAccount.sol";
import "./LibMath.sol";
import "./IReferralManager.sol";
import "./orderbook_Types.sol";
import "./Storage.sol";

library LibOrderBook {
    using LibSubAccount for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibOrder for LibOrder.OrderList;
    using LibOrder for bytes32[3];
    using LibOrder for PositionOrder;
    using LibOrder for LiquidityOrder;
    using LibOrder for WithdrawalOrder;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    event CancelOrder(uint64 orderId, OrderType orderType, bytes32[3] orderData);
    event NewLiquidityOrder(
        address indexed account,
        uint64 indexed orderId,
        uint8 assetId,
        uint96 rawAmount, // erc20.decimals
        bool isAdding
    );
    event NewPositionOrder(
        bytes32 indexed subAccountId,
        uint64 indexed orderId,
        uint96 collateral, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        uint32 deadline // 1e0. 0 if market order. > 0 if limit order
    );
    event NewPositionOrderExtra(
        bytes32 indexed subAccountId,
        uint64 indexed orderId,
        uint96 collateral, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        uint32 deadline, // 1e0. 0 if market order. > 0 if limit order
        PositionOrderExtra extra
    );

    function _transferIn(
        // storage
        IWETH _weth,
        // args
        address trader,
        address tokenAddress,
        address recipient,
        uint256 rawAmount
    ) internal {
        if (tokenAddress == address(_weth)) {
            require(msg.value > 0 && msg.value == rawAmount, "VAL"); // transaction VALue SHOULD equal to rawAmount
            _weth.deposit{ value: rawAmount }();
            if (recipient != address(this)) {
                _weth.transfer(recipient, rawAmount);
            }
        } else {
            require(msg.value == 0, "VAL"); // transaction VALue SHOULD be 0
            IERC20Upgradeable(tokenAddress).safeTransferFrom(trader, recipient, rawAmount);
        }
    }

    function _transferOut(
        // storage
        IWETH _weth,
        INativeUnwrapper _nativeUnwrapper,
        // args
        address tokenAddress,
        address recipient,
        uint256 rawAmount
    ) internal {
        if (tokenAddress == address(_weth)) {
            _weth.transfer(address(_nativeUnwrapper), rawAmount);
            INativeUnwrapper(_nativeUnwrapper).unwrap(payable(recipient), rawAmount);
        } else {
            IERC20Upgradeable(tokenAddress).safeTransfer(recipient, rawAmount);
        }
    }

    function placeLiquidityOrder(
        // storage
        ILiquidityPool _pool,
        IERC20Upgradeable _mlp,
        LibOrder.OrderList storage _orders,
        IWETH _weth,
        uint32 blockTimestamp,
        // args
        address account,
        uint64 orderId,
        uint8 assetId,
        uint96 rawAmount, // erc20.decimals
        bool isAdding
    ) external {
        require(rawAmount != 0, "A=0"); // Amount Is Zero
        if (isAdding) {
            address collateralAddress = _pool.getAssetAddress(assetId);
            LibOrderBook._transferIn(_weth, account, collateralAddress, address(this), rawAmount);
        } else {
            _mlp.safeTransferFrom(account, address(this), rawAmount);
        }
        bytes32[3] memory data = LibOrder.encodeLiquidityOrder(
            orderId,
            account,
            assetId,
            rawAmount,
            isAdding,
            blockTimestamp
        );
        _orders.add(orderId, data);
        emit NewLiquidityOrder(account, orderId, assetId, rawAmount, isAdding);
    }

    function fillLiquidityOrder(
        // storage
        ILiquidityPool _pool,
        IERC20Upgradeable _mlp,
        uint32 liquidityLockPeriod,
        uint32 blockTimestamp,
        // args
        uint96 assetPrice,
        uint96 mlpPrice,
        uint96 currentAssetValue,
        uint96 targetAssetValue,
        bytes32[3] memory orderData
    ) external {
        LiquidityOrder memory order = orderData.decodeLiquidityOrder();
        require(blockTimestamp >= order.placeOrderTime + liquidityLockPeriod, "LCK"); // mlp token is LoCKed
        uint96 rawAmount = order.rawAmount;
        if (order.isAdding) {
            IERC20Upgradeable collateral = IERC20Upgradeable(_pool.getAssetAddress(order.assetId));
            collateral.safeTransfer(address(_pool), rawAmount);
            _pool.addLiquidity(
                order.account,
                order.assetId,
                rawAmount,
                assetPrice,
                mlpPrice,
                currentAssetValue,
                targetAssetValue
            );
        } else {
            _mlp.safeTransfer(address(_pool), rawAmount);
            _pool.removeLiquidity(
                order.account,
                rawAmount,
                order.assetId,
                assetPrice,
                mlpPrice,
                currentAssetValue,
                targetAssetValue
            );
        }
    }

    function redeemMuxToken(
        // storage
        ILiquidityPool _pool,
        IWETH _weth,
        // args
        address trader,
        uint8 tokenId,
        uint96 muxTokenAmount
    ) external {
        Asset memory asset = _pool.getAssetInfo(tokenId);
        _transferIn(_weth, trader, asset.muxTokenAddress, address(_pool), muxTokenAmount);
        _pool.redeemMuxToken(trader, tokenId, muxTokenAmount);
    }

    function cancelActivatedTpslOrders(
        // storage
        LibOrder.OrderList storage _orders,
        mapping(bytes32 => EnumerableSetUpgradeable.UintSet) storage _activatedTpslOrders,
        // args
        bytes32 subAccountId
    ) external {
        EnumerableSetUpgradeable.UintSet storage orderIds = _activatedTpslOrders[subAccountId];
        uint256 length = orderIds.length();
        for (uint256 i = 0; i < length; i++) {
            uint64 orderId = uint64(orderIds.at(i));
            require(_orders.contains(orderId), "OID"); // can not find this OrderID
            bytes32[3] memory orderData = _orders.get(orderId);
            _orders.remove(orderId);
            OrderType orderType = LibOrder.getOrderType(orderData);
            require(orderType == OrderType.PositionOrder, "TYP"); // order TYPe mismatch
            PositionOrder memory order = orderData.decodePositionOrder();
            require(!order.isOpenPosition() && order.collateral == 0, "CLS"); // should be CLoSe position order and no withdraw
            emit CancelOrder(orderId, orderType, orderData);
        }
        delete _activatedTpslOrders[subAccountId];
    }

    function updatePositionOrder(
        // storage
        LibOrder.OrderList storage _orders,
        mapping(uint64 => PositionOrderExtra) storage _positionOrderExtras,
        address msgSender,
        uint32 blockTimestamp,
        // args
        uint64 orderId,
        uint64 newOrderId,
        uint96 collateralAmount, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint32 deadline, // 1e0
        PositionOrderExtra memory extra
    ) external returns (PositionOrder memory order) {
        // find and remove the old order
        require(_orders.contains(orderId), "OID"); // can not find this OrderID
        {
            bytes32[3] memory orderData = _orders.get(orderId);
            _orders.remove(orderId);
            emit CancelOrder(orderId, OrderType.PositionOrder, orderData);
            order = orderData.decodePositionOrder();
            OrderType orderType = orderData.getOrderType();
            require(orderType == OrderType.PositionOrder, "TYP"); // order TYPe mismatch
        }

        // see placePositionOrder
        require(order.subAccountId.getSubAccountOwner() == msgSender, "SND"); // SeNDer is not authorized
        require(size != 0, "S=0"); // order Size Is Zero
        if ((order.flags & LibOrder.POSITION_MARKET_ORDER) != 0) {
            require(price == 0, "P!0"); // market order does not need a limit Price
            require(deadline == 0, "D!0"); // market order does not need a deadline
        } else {
            require(deadline > blockTimestamp, "D<0"); // Deadline is earlier than now
        }

        if ((order.flags & LibOrder.POSITION_OPEN) != 0) {
            // see _placeOpenPositionOrder
            require(collateralAmount == 0, "C!0"); // can not modify collateralAmount
            collateralAmount = order.collateral;

            if ((order.flags & LibOrder.POSITION_TPSL_STRATEGY) != 0) {
                // tp/sl strategy
                require((extra.tpPrice > 0 || extra.slPrice > 0), "TPSL"); // TP/SL strategy need tpPrice and/or slPrice
                require(extra.tpslDeadline > blockTimestamp, "D<0"); // Deadline is earlier than now
                require((extra.tpslDeadline - blockTimestamp) / 10 <= type(uint24).max, "DTL"); // Deadline is Too Large
                delete _positionOrderExtras[orderId];
                _positionOrderExtras[newOrderId] = extra;
                emit NewPositionOrderExtra(
                    order.subAccountId,
                    newOrderId,
                    collateralAmount,
                    size,
                    price,
                    0 /* profitTokenId */,
                    order.flags,
                    deadline,
                    extra
                );
            }
        } else {
            // see _placeClosePositionOrder

            // should never see a tp/sl close order. because _placeClosePositionOrder should expand this
            // order into 2 orders
            require((order.flags & LibOrder.POSITION_TPSL_STRATEGY) == 0, "TPSL"); // modify a tp/sl strategy close-order is not supported.
        }

        // overwrite the order
        order.size = size;
        order.price = price;
        order.collateral = collateralAmount;

        // place a new order
        placePositionOrder(_orders, blockTimestamp, newOrderId, deadline, order);
    }

    function placePositionOrder(
        // storage
        LibOrder.OrderList storage _orders,
        uint32 blockTimestamp,
        // args
        uint64 newOrderId,
        uint32 deadline, // 1e0
        PositionOrder memory order // note: id, placeOrderTime, expire10s will be ignored
    ) public {
        uint32 expire10s;
        if (deadline > 0) {
            expire10s = (deadline - blockTimestamp) / 10;
            require(expire10s <= type(uint24).max, "DTL"); // Deadline is Too Large
        }
        bytes32[3] memory newOrderData = LibOrder.encodePositionOrder(
            newOrderId,
            order.subAccountId,
            order.collateral,
            order.size,
            order.price,
            order.profitTokenId,
            order.flags,
            blockTimestamp,
            uint24(expire10s)
        );
        _orders.add(newOrderId, newOrderData);
        emit NewPositionOrder(
            order.subAccountId,
            newOrderId,
            order.collateral,
            order.size,
            order.price,
            order.profitTokenId,
            order.flags,
            deadline
        );
    }
}

