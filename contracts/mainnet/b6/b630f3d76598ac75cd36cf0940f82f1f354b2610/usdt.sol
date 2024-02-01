// SPDX-License-Identifier: BUSDL-1.1
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import {ApyUnderlyerConstants} from "./apy.sol";

import {AaveBasePool} from "./AaveBasePool.sol";
import {ApyUnderlyerConstants} from "./apy.sol";

contract AaveUsdtZap is AaveBasePool, ApyUnderlyerConstants {
    string public constant override NAME = "aave-usdt";

    constructor() public AaveBasePool(USDT_ADDRESS, LENDING_POOL_ADDRESS) {} // solhint-disable-line no-empty-blocks
}

