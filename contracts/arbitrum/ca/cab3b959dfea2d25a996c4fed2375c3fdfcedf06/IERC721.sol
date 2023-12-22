// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 * NOTE: Modified to include symbols and decimals.
 */
interface IERC721 {
  function totalSupply() external view returns (uint256);

  function mint(address) external;

  function tokenURI(uint256) external view returns (string memory);

  function burn(uint256) external;

  function balanceOf(address) external view returns (uint256);
}

