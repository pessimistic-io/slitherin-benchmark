// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./DexAggregatorInterface.sol";
import "./OpenLevInterface.sol";
import "./IOPLimitOrder.sol";

contract LimitOrderHelper {
    constructor ()
    {
    }
    enum OrderStatus{
        HEALTHY, // Do nothing
        UPDATING_PRICE, // Need update price
        WAITING, // Waiting for 1 min before filling
        FILL, // Can fill
        NOP// No position
    }

    struct PriceVars {
        uint256 price;
        uint8 decimal;
    }

    struct OrderStatVars {
        uint256 remaining;
        uint256 lastUpdateTime;
        uint256 price0;
        uint8 decimal;
        OrderStatus status;
    }


    function getPrices(ILimitOrder limitOrder, address[] calldata token0s, address[] calldata token1s, bytes[] calldata dexDatas) external view returns (PriceVars[] memory results){
        DexAggregatorInterface dexAgg = limitOrder.dexAgg();
        results = new PriceVars[](token0s.length);
        for (uint i = 0; i < token0s.length; i++) {
            PriceVars memory item;
            (item.price, item.decimal) = dexAgg.getPrice(token0s[i], token1s[i], dexDatas[i]);
            results[i] = item;
        }
        return results;
    }

    function getOrderStat(ILimitOrder limitOrder, bytes32 orderId, uint16 marketId, bool longToken, bool isOpen, bool isStopLoss, uint256 price0, bytes memory dexData) external returns (OrderStatVars memory){
        OrderStatVars memory result;
        result.remaining = limitOrder.remainingRaw(orderId);
        result.status = OrderStatus.HEALTHY;
        if (result.remaining == 1) {
            result.status = OrderStatus.NOP;
            return result;
        }
        DexAggregatorInterface dexAgg = limitOrder.dexAgg();
        OpenLevInterface openLev = limitOrder.openLev();
        OpenLevInterface.Market memory market = openLev.markets(marketId);
        (
        result.price0,,,result.decimal, result.lastUpdateTime) = dexAgg.getPriceCAvgPriceHAvgPrice(market.token0, market.token1, 60, dexData);
        if (isOpen) {
            if ((!longToken && result.price0 <= price0) || (longToken && result.price0 >= price0)) {
                result.status = OrderStatus.FILL;
            }
            return result;
        }
        if (!isStopLoss) {
            if ((!longToken && result.price0 >= price0) || (longToken && result.price0 <= price0)) {
                result.status = OrderStatus.FILL;
            }
            return result;
        }
        // stop loss
        if ((!longToken && result.price0 <= price0) || (longToken && result.price0 >= price0)) {
            openLev.updatePrice(marketId, dexData);
            (,uint cAvgPrice,uint hAvgPrice,,) = dexAgg.getPriceCAvgPriceHAvgPrice(market.token0, market.token1, 60, dexData);
            if ((!longToken && cAvgPrice <= price0 && (hAvgPrice <= price0 || block.timestamp >= result.lastUpdateTime + 60)) || (longToken && cAvgPrice >= price0 && (hAvgPrice >= price0 || block.timestamp >= result.lastUpdateTime + 60))) {
                result.status = OrderStatus.FILL;
                return result;
            }
            if ((!longToken && (cAvgPrice >= price0 && block.timestamp >= result.lastUpdateTime + 60)) || (longToken && (cAvgPrice <= price0 && block.timestamp >= result.lastUpdateTime + 60))) {
                if (toDex(dexData) != 2) {
                    result.status = OrderStatus.UPDATING_PRICE;
                }
                // uni v3
                else {
                    result.status = OrderStatus.WAITING;
                }
                return result;
            }
            result.status = OrderStatus.WAITING;
            return result;
        }
        return result;
    }

    function toDex(bytes memory data) internal pure returns (uint8) {
        require(data.length >= 1, "DexData: toDex wrong data format");
        uint8 temp;
        assembly {
            temp := byte(0, mload(add(data, add(0x20, 0))))
        }
        return temp;
    }
}

interface ILimitOrder {
    function dexAgg() external view returns (DexAggregatorInterface);

    function openLev() external view returns (OpenLevInterface);

    function remainingRaw(bytes32 _orderId) external view returns (uint256);

}


