//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./NonblockingLzApp.sol";

contract GaugeSnapshotReceiver is NonblockingLzApp {
    mapping(address => Snapshot[]) public snapshots;

    struct Snapshot {
        address gaugeAddress;
        uint256 timestamp;
        uint256 totalSupply;
    }

    constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) {}

    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory payload) internal override {
      Snapshot[] memory newSnapshots = abi.decode(payload, (Snapshot[]));
      for (uint i = 0; i < newSnapshots.length; ++i)
          snapshots[newSnapshots[i].gaugeAddress].push(newSnapshots[i]);
    }

    function getSnapshotsLength(address _address) public view returns (uint length) {
        return snapshots[_address].length;
    }
}
