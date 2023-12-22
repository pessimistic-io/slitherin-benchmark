// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

abstract contract BaseCommissionManager is Ownable {

    uint96 public immutable slippage;

    uint96 public immutable denominator;

    uint96 public fraction;

    constructor() {
        slippage = 8500;
        denominator = 10000;
        fraction = 200;
    }

    function setFraction(uint96 fraction_) external onlyOwner {
        fraction = fraction_;
    }

}

