// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PaymentSplitter} from "./PaymentSplitter.sol";
import {Ownable} from "./Ownable.sol";

contract PaymentSplitterFactory is Ownable {
    constructor() {}

    function createPaymentSplitter(
        address[] memory payees,
        uint256[] memory shares
    ) public onlyOwner returns (address) {
        PaymentSplitter paymentSplitter = new PaymentSplitter(payees, shares);
        return address(paymentSplitter);
    }
}

