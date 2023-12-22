// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

abstract contract BaseRecipient is Ownable {

    address public recipient;

    constructor(address recipient_) {
        recipient = recipient_;
    }

    function setRecipient(address recipient_) external onlyOwner {
        recipient = recipient_;
    }

}

