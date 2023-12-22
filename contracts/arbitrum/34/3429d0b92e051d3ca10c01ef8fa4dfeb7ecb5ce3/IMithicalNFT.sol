// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 * NOTE: Modified to include symbols and decimals.
 */
interface IMithicalNFT {
  function totalSupply() external view returns (uint256);

  function minterMint(address, uint256) external;
}

