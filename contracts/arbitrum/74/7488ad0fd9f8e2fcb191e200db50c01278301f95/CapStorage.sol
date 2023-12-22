// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {DS} from "./IDataStore.sol";

contract CapStorage {
    uint256 public constant BPS_DIVIDER = 10000;
    DS public ds;
    //address public owner;
    address public MARKET_STORE;
    address public FUND_STORE;
    address public ORDERS;
    address public PROCESSOR;
    address public ORDER_STORE;
}

