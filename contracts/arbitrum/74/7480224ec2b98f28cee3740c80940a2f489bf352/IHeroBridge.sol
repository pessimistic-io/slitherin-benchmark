pragma solidity ^0.8.0;
//SPDX-License-Identifier: UNLICENSED

// Interface for Elleria's Heroes.
contract IHeroBridge {
  function GetOwnerOfTokenId(uint256 _tokenId) external view returns (address) {}
}
