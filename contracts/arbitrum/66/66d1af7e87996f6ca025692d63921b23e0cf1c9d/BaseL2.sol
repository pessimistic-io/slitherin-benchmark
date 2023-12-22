// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

abstract contract BaseL2 is Ownable {

    address public l2;

    constructor(address l2_) {
        l2 = l2_;
    }

    function setL2(address l2_) external onlyOwner {
        l2 = l2_;
    }

}

