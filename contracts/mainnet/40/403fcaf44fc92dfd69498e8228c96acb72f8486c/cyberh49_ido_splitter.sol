// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PaymentSplitter.sol";

contract NounGANSplitter is PaymentSplitter {

    address cyberh49 = 0xA422bfFF5dABa6eeeFAFf84Debf609Edf0868C5f;
    address magic = 0xc7c6D5da121a293f148DF347454f27E82D6cad7e;

    address[] team_addresses = [cyberh49, magic];
    uint256[] team_shares = [1, 1];

    constructor() PaymentSplitter(team_addresses, team_shares) { }

    fallback() external payable { }
}

