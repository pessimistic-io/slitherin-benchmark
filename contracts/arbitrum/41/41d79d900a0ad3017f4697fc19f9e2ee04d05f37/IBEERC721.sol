// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IERC721.sol";

interface IBEERC721 is IERC721 {
  function mint(address to, uint256 tokenId) external;

  function batchMint(
    address to,
    uint256 count
  ) external returns (uint256[] memory);

  function burn(address owner, uint256 tokenId) external;

  function ownerOf(uint256 tokenId) external view returns (address owner);

  function isLocked(uint256 tokenId) external view returns (bool);
}

