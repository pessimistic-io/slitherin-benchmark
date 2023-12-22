//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Tools for Externally Owned Accounts

abstract contract EOA {
  modifier onlyEOA () {
    require(_isEOA(msg.sender), 'EOA_UNAUTHORIZED');
    _;
  }

  function _isEOA (address sender) internal view returns (bool) {
    return sender == tx.origin;
  }
}
