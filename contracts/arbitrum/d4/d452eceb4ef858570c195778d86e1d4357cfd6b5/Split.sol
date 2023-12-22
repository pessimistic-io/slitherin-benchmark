// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import "./PaymentSplitter.sol";

contract Split is PaymentSplitter {
    constructor(address[] memory receivers, uint256[] memory shares_)
        payable
        PaymentSplitter(receivers, shares_)
    {}
}

