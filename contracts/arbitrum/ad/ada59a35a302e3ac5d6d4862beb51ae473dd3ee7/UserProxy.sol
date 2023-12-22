// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./IHasUpstream.sol";
import "./Proxy.sol";

contract UserProxy is Proxy {
  constructor(
    address owner,
    address eternalStorage,
    address frontDoor
  ) Proxy(owner, eternalStorage, frontDoor, true) {}

  function getUpstream() external view override returns (address) {
    IHasUpstream frontDoor = IHasUpstream(upstreamAddress);
    return frontDoor.getUpstream();
  }
}

