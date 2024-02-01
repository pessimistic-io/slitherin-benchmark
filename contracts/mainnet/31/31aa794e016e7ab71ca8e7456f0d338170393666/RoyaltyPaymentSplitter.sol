// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "./PaymentSplitter.sol";

contract RoyaltyPaymentSplitter is PaymentSplitter {
  constructor(address[] memory payees, uint256[] memory shares_)
    PaymentSplitter(payees, shares_)
  {}
}
