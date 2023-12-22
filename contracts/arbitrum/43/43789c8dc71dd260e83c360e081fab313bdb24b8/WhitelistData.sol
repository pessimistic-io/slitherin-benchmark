// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Ownable.sol";
import "./ERC20.sol";

contract WhitelistData is Ownable {
  // Whitelist will have the last IDs not to disturb the auction contract
  uint public endOfWl = 4009;
  uint public wlDataLength = 0;

  struct Account {
    uint tokenId;
    bool exists;
  }

  mapping(address => Account) public accounts;

  function bulkAddWhitelistAccounts(address[] memory _accounts) public onlyOwner {
    uint startOfWl = endOfWl - _accounts.length;
    for(uint i = 0; i < _accounts.length; i++) {
      accounts[_accounts[i]] = Account(startOfWl + i, true);
      wlDataLength++;
    }
  }

  function addWhitelistAccount(address _account) public onlyOwner {
    accounts[_account] = Account(wlDataLength, true);
    wlDataLength++;
  }

  function getWhitelistAccount(address _account) public view returns (Account memory) {
    return accounts[_account];
  }
}

