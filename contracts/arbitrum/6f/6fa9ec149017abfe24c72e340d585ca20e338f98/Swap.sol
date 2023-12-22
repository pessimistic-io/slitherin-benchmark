// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20Metadata} from "./IERC20Metadata.sol";

import "./errors.sol";
import {ISwapFactory} from "./ISwapFactory.sol";
import {DefiOp} from "./DefiOp.sol";

abstract contract Swap is DefiOp {
    modifier checkToken(address token) {
        if (!ISwapFactory(factory).isTokenWhitelisted(token))
            revert UnsupportedToken();
        _;
    }
}

