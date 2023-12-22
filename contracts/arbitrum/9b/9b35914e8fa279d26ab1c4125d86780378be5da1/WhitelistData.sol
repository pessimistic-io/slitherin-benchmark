// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Ownable.sol";
import "./ERC20.sol";

contract WhitelistData is Ownable {
  uint public wlDataLength = 0;

  mapping(address => bool) public accounts;

  function bulkAddWhitelistAccounts(address[] memory _accounts) public onlyOwner {
    for(uint i = 0; i < _accounts.length; i++) {
      addWhitelistAccount(_accounts[i]);
    }
  }

  function addWhitelistAccount(address _account) public onlyOwner {
    accounts[_account] = true;
    wlDataLength++;
  }

  function isWhitelisted(address _account) public view returns (bool) {
    return accounts[_account];
  }
}

