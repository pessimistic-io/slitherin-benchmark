// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface INitroPool {
  function withdraw(uint256 tokenId) external;
  function emergencyWithdraw(uint256 tokenId) external;
  function harvest() external;
  function nftPool() external view returns (address);
  function userInfo(address user) external view returns (uint256, uint256, uint256, uint256, uint256);
}
