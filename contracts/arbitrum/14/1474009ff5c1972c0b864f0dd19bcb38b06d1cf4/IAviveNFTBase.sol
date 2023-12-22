// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAviveNFTBase {
  /**
   * @notice Gets total number of tokens in existence, burned tokens will reduce the count.
   */
  function totalSupply() external view returns (uint256);

  /**
   * @notice Withdraws `amount` of `token` from the contract
   */
  function withdraw(uint256 amount) external;

  /**
   * @notice Withdraws `amount` of `token` from the contract
   */
  function withdrawToken(address token, uint256 amount) external;
}

