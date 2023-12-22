// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Fiat24Token.sol";

contract Fiat24CHF is Fiat24Token {

  function initialize(address fiat24AccountProxyAddress, uint256 limitWalkin, uint256 chfRate, uint256 withdrawCharge) public initializer {
      __Fiat24Token_init_(fiat24AccountProxyAddress, "Fiat24 CHF", "CHF24", limitWalkin, chfRate, withdrawCharge);
  }
}

