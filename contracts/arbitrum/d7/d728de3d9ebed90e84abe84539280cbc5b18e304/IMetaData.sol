// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IMetaData {
  function getMetaData(
    address token,
    uint256 tokenId
  ) external view returns (string memory);
}

