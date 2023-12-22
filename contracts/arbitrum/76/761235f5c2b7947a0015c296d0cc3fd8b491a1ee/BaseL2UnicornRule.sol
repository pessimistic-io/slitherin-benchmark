// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

abstract contract BaseL2UnicornRule is Ownable {

    address public l2UnicornRule;

    constructor(address l2UnicornRule_) {
        l2UnicornRule = l2UnicornRule_;
    }

    function setL2UnicornRule(address l2UnicornRule_) external onlyOwner {
        l2UnicornRule = l2UnicornRule_;
    }

}

