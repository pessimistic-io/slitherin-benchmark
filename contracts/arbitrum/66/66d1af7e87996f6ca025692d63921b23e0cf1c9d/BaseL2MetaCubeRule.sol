// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

abstract contract BaseL2MetaCubeRule is Ownable {

    address public l2MetaCubeRule;

    constructor(address l2MetaCubeRule_) {
        l2MetaCubeRule = l2MetaCubeRule_;
    }

    function setL2MetaCubeRule(address l2MetaCubeRule_) external onlyOwner {
        l2MetaCubeRule = l2MetaCubeRule_;
    }

}

