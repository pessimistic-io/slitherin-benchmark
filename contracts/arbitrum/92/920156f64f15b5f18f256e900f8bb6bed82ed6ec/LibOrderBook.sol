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
    event UpdatePositionOrder(
        bytes32 indexed subAccountId,
        uint64 indexed orderId,
        uint96 collateral, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        uint32 deadline // 1e0. 0 if market order. > 0 if limit order
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
        address msgSender,
        uint32 blockTimestamp,
        // args
        uint64 orderId,
        uint96 collateralAmount, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint32 deadline // 1e0
    ) external returns (PositionOrder memory order) {
        require(_orders.contains(orderId), "OID"); // can not find this OrderID
        {
            bytes32[3] memory orderData = _orders.get(orderId);
            _orders.remove(orderId);
            order = orderData.decodePositionOrder();
            OrderType orderType = orderData.getOrderType();
            require(orderType == OrderType.PositionOrder, "TYP"); // order TYPe mismatch
        }
        require(order.subAccountId.getSubAccountOwner() == msgSender, "SND"); // SeNDer is not authorized
        require(size != 0, "S=0"); // order Size Is Zero
        if ((order.flags & LibOrder.POSITION_MARKET_ORDER) != 0) {
            require(deadline == 0, "D!0"); // market order does not need a deadline
        } else {
            require(deadline > blockTimestamp, "D<0"); // Deadline is earlier than now
        }

        if ((order.flags & LibOrder.POSITION_OPEN) != 0) {
            // open
            require(collateralAmount == 0, "C!0"); // can not modify collateralAmount
            collateralAmount = order.collateral;
        } else {
            // close
            require((order.flags & LibOrder.POSITION_TPSL_STRATEGY) == 0, "TPSL"); // modify a tp/sl strategy close-order is not supported. NOTE: never here
        }
        order.size = size;
        order.price = price;
        order.collateral = collateralAmount;
        _updatePositionOrderPart2(order, _orders, blockTimestamp, orderId, deadline);
    }

    function _updatePositionOrderPart2(
        // storage
        PositionOrder memory order,
        LibOrder.OrderList storage _orders,
        uint32 blockTimestamp,
        // args
        uint64 orderId,
        uint32 deadline // 1e0
    ) private {
        uint32 expire10s;
        if (deadline > 0) {
            expire10s = (deadline - blockTimestamp) / 10;
            require(expire10s <= type(uint24).max, "DTL"); // Deadline is Too Large
        }
        bytes32[3] memory newOrderData = LibOrder.encodePositionOrder(
            orderId,
            order.subAccountId,
            order.collateral,
            order.size,
            order.price,
            order.profitTokenId,
            order.flags,
            blockTimestamp,
            uint24(expire10s)
        );
        _orders.add(orderId, newOrderData);
        emit UpdatePositionOrder(
            order.subAccountId,
            orderId,
            order.collateral,
            order.size,
            order.price,
            order.profitTokenId,
            order.flags,
            deadline
        );
    }
}

