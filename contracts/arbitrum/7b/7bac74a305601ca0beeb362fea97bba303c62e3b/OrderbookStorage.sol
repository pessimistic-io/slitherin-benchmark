// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./Admin.sol";

abstract contract OrderbookStorage is Admin {
    address public implementation;

    bool internal _mutex;

    modifier _reentryLock_() {
        require(!_mutex, "Router: reentry");
        _mutex = true;
        _;
        _mutex = false;
    }

    // executor => active
    mapping(address => bool) public isExecutor;

    struct Order {
        bool isIsolated;
        address pool;
        address account;
        uint256 index;
        address asset; // The token used for margin, address(0) for ETH
        int256 amount; // The amount of margin
        string symbolName;
        uint256 executionFee;
        int256[] orderParams; // 0:trigerPrice, 1:isAboveTrigerPrice, 2: isIndexPrice, 3:volume, 4: priceLimit
    }

    // account -> index -> Order
	mapping (address => mapping(uint256 => Order)) public orders;
    mapping (address => uint256) public ordersIndex;

    mapping (address => address) public routers;
    address public isolatedRouter;
}

