// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import {SafeCast} from "./SafeCast.sol";
import "./OrderLib.sol";

library Order {
    using SafeCast for uint256;
    using Order for Props;

    uint8 public constant STRUCT_VERSION = 0x01;

    struct Props {
        uint8 version;
        uint32 updatedAtBlock;
        uint8 triggerAbove;
        address account;
        uint48 extra3; // close: isKeepLev
        uint128 collateral;
        // open:pay; close:collateralDelta

        uint128 size;
        uint128 price;
        uint128 extra1; // open:tp
        uint64 orderID;
        uint64 extra2; //close: order to order id
        uint128 extra0; // open:sl; close:from order
        bytes32 refCode; //160
        //96 todo uint96 extra4;
    }

    function setIsFromMarket(
        Props memory order,
        bool isIncrease,
        bool _isFromMarket
    ) internal pure {
        if (isIncrease) order.extra3 = uint48(_isFromMarket ? 1 : 0);
        else order.extra1 = uint128(_isFromMarket ? 1 : 0);
    }

    function isFromMarket(
        Props memory order,
        bool isIncrease
    ) internal pure returns (bool) {
        if (isIncrease) return order.extra3 > 0;
        return order.extra1 > 0;
    }

    function setSize(Props memory order, uint256 size) internal pure {
        order.size = size.toUint128();
    }

    function setTriggerAbove(
        Props memory order,
        bool triggerAbove
    ) internal pure {
        order.triggerAbove = triggerAbove ? 1 : 2;
    }

    function getTriggerAbove(Props memory order) internal pure returns (bool) {
        if (order.triggerAbove == 1) {
            return true;
        }
        if (order.triggerAbove == 2) {
            return false;
        }
        revert("invalid order trigger above");
    }

    function isMarkPriceValid(
        Props memory order,
        uint256 markPrice
    ) internal pure returns (bool) {
        if (order.getTriggerAbove()) return markPrice >= uint256(order.price);
        else return markPrice <= uint256(order.price);
    }

    function setPrice(Props memory order, uint256 _p) internal pure {
        order.price = _p.toUint128();
    }

    //========================================
    //        extra0
    //========================================

    function setFromOrder(Props memory order, uint64 orderID) internal pure {
        order.extra0 = uint128(orderID);
    }

    function getFromOrder(Props memory order) internal pure returns (uint256) {
        return uint256(order.extra0);
    }

    function setStoploss(Props memory order, uint256 stoploss) internal pure {
        order.extra0 = stoploss.toUint128();
    }

    function getStoploss(Props memory order) internal pure returns (uint256) {
        return uint256(order.extra0);
    }

    //========================================
    //        extra1
    //========================================

    function setTakeprofit(Props memory order, uint256 tp) internal pure {
        order.extra1 = tp.toUint128();
    }

    function getTakeprofit(Props memory order) internal pure returns (uint256) {
        return order.extra1;
    }

    //========================================
    //        extra2
    //========================================

    function setPairKey(Props memory order, uint64 orderID) internal pure {
        order.extra2 = orderID;
    }

    function getPairKey(Props memory order) internal pure returns (bytes32) {
        return OrderLib.getKey(order.account, order.extra2);
    }

    //========================================
    //        extra3
    //========================================

    function setIsKeepLev(Props memory order, bool isKeepLev) internal pure {
        order.extra3 = isKeepLev ? 1 : 0;
    }

    function getIsKeepLev(Props memory order) internal pure returns (bool) {
        return order.extra3 > 0;
    }

    //========================================

    function validTPSL(Props memory _order, bool _isLong) internal pure {
        if (_order.getTakeprofit() > 0) {
            require(
                _order.getTakeprofit() > _order.price == _isLong,
                "OrderBook:tp<price"
            );
        }
        if (_order.getStoploss() > 0) {
            require(
                _order.price > _order.getStoploss() == _isLong,
                "OrderBook:sl>price"
            );
        }
    }

    function getKey(Props memory order) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(order.account, order.orderID));
    }

    function updateTime(Order.Props memory _order) internal view {
        _order.updatedAtBlock = uint32(block.timestamp);
    }

    function validOrderAccountAndID(Order.Props memory order) internal pure {
        require(order.account != address(0), "invalid order key");
        require(order.orderID != 0, "invalid order key");
    }
}

