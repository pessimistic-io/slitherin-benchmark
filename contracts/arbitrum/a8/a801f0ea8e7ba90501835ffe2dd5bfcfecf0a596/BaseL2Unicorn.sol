// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

abstract contract BaseL2Unicorn is Ownable {

    address public l2Unicorn;

    constructor(address l2Unicorn_) {
        l2Unicorn = l2Unicorn_;
    }

    function setL2Unicorn(address l2Unicorn_) external onlyOwner {
        l2Unicorn = l2Unicorn_;
    }

}

