// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./IERC20.sol";

interface IOnChainMetadata {
  /**
   * Mint new tokens.
   */
  function tokenURI(uint256 tokenId_) external view returns (string memory);

  function tokenImageDataURI(uint256 tokenId_) external view returns (string memory);
}

