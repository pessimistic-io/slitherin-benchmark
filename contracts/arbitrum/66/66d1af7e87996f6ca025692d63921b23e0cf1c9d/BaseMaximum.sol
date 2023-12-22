// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

abstract contract BaseMaximum is Ownable {

    uint8 public maximum;

    constructor(uint8 maximum_) {
        maximum = maximum_;
    }

    function setMaximum(uint8 maximum_) external onlyOwner {
        maximum = maximum_;
    }

}

