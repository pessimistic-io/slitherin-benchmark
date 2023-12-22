// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./Ownable.sol";

contract FreeMarketBase is Ownable {
  // TODO create getters
  address public eternalStorageAddress;
  address public upstreamAddress;
  bool public isUserProxy;

  constructor(
    address owner,
    address eternalStorage,
    address upstream,
    bool userProxy
  ) Ownable(owner) {
    eternalStorageAddress = eternalStorage;
    upstreamAddress = upstream;
    isUserProxy = userProxy;
  }
}

