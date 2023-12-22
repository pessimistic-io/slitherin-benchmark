pragma solidity ^0.8.0;
//SPDX-License-Identifier: UNLICENSED

// Interface for Elleria's Heroes.
contract IEllerianHero {

  function safeTransferFrom (address _from, address _to, uint256 _tokenId) public {}
  function safeTransferFrom (address _from, address _to, uint256 _tokenId, bytes memory _data) public {}

  function mintUsingToken(address _recipient, uint256 _amount, uint256 _variant) public {}

  function burn (uint256 _tokenId, bool _isBurnt) public {}

  function ownerOf(uint256 tokenId) external view returns (address owner) {}
  function isApprovedForAll(address owner, address operator) external view returns (bool) {}
}
