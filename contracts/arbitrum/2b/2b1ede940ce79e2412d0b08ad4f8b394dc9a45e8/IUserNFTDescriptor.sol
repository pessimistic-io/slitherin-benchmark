// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IUserNFTDescriptor {
  function tokenURI(address hub, uint256 tokenId) external view returns (string memory);
}
