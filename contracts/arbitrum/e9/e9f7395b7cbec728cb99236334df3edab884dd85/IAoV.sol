// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IAoV {
  function burn(uint256 _tokenId) external;

  function mintFor(address _for, uint256 _quantity) external returns (uint256);
}

