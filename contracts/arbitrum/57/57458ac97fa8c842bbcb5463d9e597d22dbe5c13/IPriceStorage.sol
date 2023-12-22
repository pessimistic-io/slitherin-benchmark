// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

abstract contract IPriceStorage {
    function _price(address token) internal virtual view returns (uint);
    function _price(address token, uint price) internal virtual;
    function _delPrice(address token) internal virtual;
    function _addTokenToPrice(address token) internal virtual;
}
