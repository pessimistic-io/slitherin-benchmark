// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./WaveContract.sol";

contract WaveFactory is Ownable, IWaveFactory {
  address[] public waves;
  address public override keeper;

  event WaveCreated(address indexed wave, address indexed owner);

  constructor(address _keeper) Ownable() {
    keeper = _keeper;
  }

  function changeKeeper(address _keeper) public onlyOwner {
    keeper = _keeper;
  }

  function deployWave(
    string memory _name,
    string memory _symbol,
    string memory _baseURI,
    bytes32 _root,
    uint256 _startTimestamp,
    uint256 _endTimestamp
  ) public override {
    WaveContract wave = new WaveContract(
      _name,
      _symbol,
      _baseURI,
      _root,
      _startTimestamp,
      _endTimestamp
    );
    waves.push(address(wave));
    wave.transferOwnership(msg.sender);
    emit WaveCreated(address(wave), msg.sender);
  }
}

