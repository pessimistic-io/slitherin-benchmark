// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.16;

import {TokenCheck} from "./Swap.sol";

struct UseParams {
    uint256 chain;
    address account;
    TokenCheck[] ins;
    uint256[] inAmounts;
    TokenCheck[] outs;
    bytes args;
    address msgSender;
    bytes msgData;
}

interface IUseProtocol {
    function use(UseParams calldata params) external payable;
}

