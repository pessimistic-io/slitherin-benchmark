// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract Notion {
    error NotANotion(address token);

    address immutable _notion;

    constructor(address notion_) {
        _notion = notion_;
    }

    function _checkNotion(address token) internal view {
        if (token != _notion) {
            revert NotANotion(token);
        }
    }
}

