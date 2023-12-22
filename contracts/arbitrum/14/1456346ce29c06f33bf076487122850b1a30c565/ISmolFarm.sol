// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface ISmolFarm {
  function ownsToken(address _collection, address _owner, uint256 _tokenId) external view returns (bool);
}

