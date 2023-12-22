// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./Ownable.sol";
import "./ERC20.sol";

contract HarvestWhitelistData is Ownable {
  uint public wlDataLength = 0;

  mapping(address => bool) public accounts;

  // add accounts to whitelist
  function bulkAddWhitelistAccounts(address[] memory _accounts) public onlyOwner {
    for(uint i = 0; i < _accounts.length; i++) {
      addWhitelistAccount(_accounts[i]);
    }
  }

  function addWhitelistAccount(address _account) public onlyOwner {
    accounts[_account] = true;
    wlDataLength++;
  }

  // remove accounts from whitelist
  function bulkRemoveWhitelistAccounts(address[] memory _accounts) public onlyOwner {
    for(uint i = 0; i < _accounts.length; i++) {
      removeWhitelistAccount(_accounts[i]);
    }
  }

  function removeWhitelistAccount(address _account) public onlyOwner {
    accounts[_account] = false;
    wlDataLength--;
  }

  // check account is whitelisted
  function isWhitelisted(address _account) public view returns (bool) {
    return accounts[_account];
  }
}

