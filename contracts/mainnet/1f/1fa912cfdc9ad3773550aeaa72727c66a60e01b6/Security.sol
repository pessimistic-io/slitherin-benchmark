// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.13;

import "./Address.sol";

contract Security {
    /// @dev Check if caller is a wallet
  modifier isEOA() {
      require(!(Address.isContract(msg.sender)) && tx.origin == msg.sender, "Only EOA");
      _;
  }
}
