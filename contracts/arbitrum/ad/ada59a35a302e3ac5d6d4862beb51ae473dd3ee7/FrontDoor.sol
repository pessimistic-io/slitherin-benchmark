// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./EternalStorage.sol";
import "./Proxy.sol";
import "./LibStorageWriter.sol";

contract FrontDoor is Proxy {
  constructor() Proxy(msg.sender, address(new EternalStorage(msg.sender, address(this))), address(0x0), false) {
    bytes32 key = keccak256(abi.encodePacked('frontDoor'));
    StorageWriter.setAddress(eternalStorageAddress, key, address(this));
  }

  event UpstreamChanged(address oldUpstream, address newUpstream);

  function setUpstream(address newUpstream) public onlyOwner {
    address oldUpstream = upstreamAddress;
    upstreamAddress = newUpstream;
    emit UpstreamChanged(oldUpstream, newUpstream);
  }
}

