// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

abstract contract BaseL2MetaCube is Ownable {

    address public l2MetaCube;

    constructor(address l2MetaCube_) {
        l2MetaCube = l2MetaCube_;
    }

    function setL2MetaCube(address l2MetaCube_) external onlyOwner {
        l2MetaCube = l2MetaCube_;
    }

}

