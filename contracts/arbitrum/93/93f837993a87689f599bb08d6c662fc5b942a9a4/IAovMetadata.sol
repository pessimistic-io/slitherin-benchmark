// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IAovMetadata {
  function uri(address _addr, uint256 _tokenId)
    external
    view
    returns (string memory);
}

