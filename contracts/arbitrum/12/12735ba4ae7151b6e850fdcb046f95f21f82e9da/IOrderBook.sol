// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;
import "./OrderStruct.sol";
import {IOrderStore} from "./IOrderStore.sol";
import {OrderLib} from "./OrderLib.sol";
import "./MarketDataTypes.sol";

interface IOrderBook {
    function initialize(
        bool _isLong,
        address _openStore,
        address _closeStore
    ) external;

    function add(
        MarketDataTypes.UpdateOrderInputs[] memory _vars
    ) external returns (Order.Props[] memory _orders);

    function update(
        MarketDataTypes.UpdateOrderInputs memory _vars
    ) external returns (Order.Props memory);

    function removeByAccount(
        bool isOpen,
        address account
    ) external returns (Order.Props[] memory _orders);

    function remove(
        address account,
        uint256 orderID,
        bool isOpen
    ) external returns (Order.Props[] memory _orders);

    function remove(
        bytes32 key,
        bool isOpen
    ) external returns (Order.Props[] memory _orders);

    //=============================
    function openStore() external view returns (IOrderStore);

    function closeStore() external view returns (IOrderStore);

    function getExecutableOrdersByPrice(
        uint256 start,
        uint256 end,
        bool isOpen,
        uint256 _oraclePrice
    ) external view returns (Order.Props[] memory _orders);
}

