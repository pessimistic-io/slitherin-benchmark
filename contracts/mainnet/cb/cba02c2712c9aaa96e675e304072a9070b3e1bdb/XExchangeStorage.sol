// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IWeth} from "./IWeth.sol";
import {ITransferManagerSelector} from "./ITransferManagerSelector.sol";
import {IRoyaltyEngine} from "./IRoyaltyEngine.sol";
import {IMarketplaceFeeEngine} from "./IMarketplaceFeeEngine.sol";
import {IStrategyManager} from "./IStrategyManager.sol";
import {ICurrencyManager} from "./ICurrencyManager.sol";

contract XExchangeStorage {
    bytes32 public domainSeperator;
    IWeth public weth;

    ITransferManagerSelector public transferManager;
    IRoyaltyEngine public royaltyEngine;
    IMarketplaceFeeEngine public marketplaceFeeEngine;
    IStrategyManager public strategyManager;
    ICurrencyManager public currencyManager;
    mapping(address => uint256) public userMinNonce;
    mapping(bytes32 => bool) public orderStatus;
}

