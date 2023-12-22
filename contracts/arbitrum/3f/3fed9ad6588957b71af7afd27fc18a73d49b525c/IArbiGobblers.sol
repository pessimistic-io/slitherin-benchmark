// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IArbiGobblers {
  // struct to store each token's traits
  struct HumanArbiGobblers {
    bool isHuman;
    uint8 levelIndex;
  }

  function getGen(uint256 tokenId) external view returns(uint8);

  function getClassId(uint256 tokenId) external view returns(uint256);
  
  function getTokenTraits(uint256 tokenId)
      external
      view
      returns (HumanArbiGobblers memory);
}


