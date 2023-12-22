// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import "./Ownable.sol";

interface IWhitelist {
  function isWhitelisted(address) external view returns (bool);
}

interface ISentimentRegistry {
  function ownerFor(address) external view returns (address);
}

contract Whitelist is IWhitelist, Ownable {
  mapping(address => bool) public _isWhitelisted;

  constructor(address _gov) {
    transferOwnership(_gov);
  }

  function isWhitelisted(address _addr) public view returns (bool) {
    return _isWhitelisted[_addr] || isSentimentAccount(_addr);
  }

  function isSentimentAccount(address _addr) public view returns (bool) {
    return
      ISentimentRegistry(0x17B07cfBAB33C0024040e7C299f8048F4a49679B).ownerFor(_addr) != address(0);
  }

  function whitelistAdd(address _addr) external onlyOwner {
    _isWhitelisted[_addr] = true;
    emit AddedToWhitelist(_addr);
  }

  function whitelistRemove(address _addr) external onlyOwner {
    _isWhitelisted[_addr] = false;
    emit RemovedFromWhitelist(_addr);
  }

  event RemovedFromWhitelist(address indexed _addr);
  event AddedToWhitelist(address indexed _addr);
}

