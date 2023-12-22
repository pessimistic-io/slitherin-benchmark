// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

interface IItemMetadata {
  function getMetadata(uint256 _tokenId) external view returns (string memory);

  function isBound(uint256 _tokenId) external view returns (bool);

  function name(uint256 _tokenId) external view returns (string memory);
}

