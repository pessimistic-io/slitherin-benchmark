// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract Notion {
    address immutable NOTION;

    error NotANotion(address token);

    constructor(address notion) {
        NOTION = notion;
    }

    function _checkNotion(address token) internal view {
        if (token != NOTION) {
            revert NotANotion(token);
        }
    }
}

