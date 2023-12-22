// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;
import "./OrderStruct.sol";

interface IOrderStore {
    function initialize(bool _isLong) external;

    function add(Order.Props memory order) external;

    function set(Order.Props memory order) external;

    function remove(bytes32 key) external returns (Order.Props memory order);

    function delByAccount(
        address account
    ) external returns (Order.Props[] memory _orders);

    function generateID(address _acc) external returns (uint256);

    function setOrderBook(address _ob) external;

    //============================
    function orders(bytes32 key) external view returns (Order.Props memory);

    function getOrderByAccount(
        address account
    ) external view returns (Order.Props[] memory _orders);

    function getKey(uint256 _index) external view returns (bytes32);

    function getKeys(
        uint256 start,
        uint256 end
    ) external view returns (bytes32[] memory);

    function containsKey(bytes32 key) external view returns (bool);

    function isLong() external view returns (bool);

    // function orderTotalSize(address) external view returns (uint256) ;
    function getCount() external view returns (uint256);

    function orderNum(address _a) external view returns (uint256); // 用户的order数量
}

