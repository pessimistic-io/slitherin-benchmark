// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ITokenVesting.sol";

interface ICSS is IERC20 {
  function cap() external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function MINTER_ROLE() external view returns (bytes32);
  function safeMint(address, uint256) external returns (uint256);
  function hasRole(bytes32 role, address account) external view returns (bool);
  function tokenVesting() external view returns (ITokenVesting);
  function rescueTokens(IERC20[] calldata tokens) external;
}

