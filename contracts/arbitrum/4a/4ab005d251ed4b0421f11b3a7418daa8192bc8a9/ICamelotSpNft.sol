// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICamelotSpNft {
  function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

  function getStakingPosition(uint256 tokenId)
    external
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    );

  function addToPosition(uint256 tokenId, uint256 amountToAdd) external;

  function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external;

  function harvestPosition(uint256 tokenId) external;
}

