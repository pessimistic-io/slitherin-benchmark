// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ONFT721.sol";

contract BensLz is ONFT721 {
  address _admin;

  string literallyMe = "ipfs://QmWGkeKwvbg7hmiQ5jfBoU1SNpXFE9Xd96VJnYThr7NTs1";

  constructor(
    uint256 _minGasToStore,
    address _layerZeroEndpoint
  ) ONFT721("BensLz", "BLZ", _minGasToStore, _layerZeroEndpoint) {
    _admin = msg.sender;
  }

  function mintTokens(address _to, uint256 _id) external {
    require(msg.sender == _admin, "ERR");
    _mint(_to, _id);
  }

  function tokenURI(uint256) public view override returns (string memory) {
    return literallyMe;
  }
}

