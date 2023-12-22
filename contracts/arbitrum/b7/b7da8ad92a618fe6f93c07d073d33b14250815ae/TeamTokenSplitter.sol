//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

//import payment splitter
import "./PaymentSplitter.sol";

contract KarrotTeamSplitter is PaymentSplitter {

    constructor (address[] memory payees, uint256[] memory shares_) PaymentSplitter(payees, shares_) {}

}

