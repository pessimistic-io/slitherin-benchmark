// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

interface IToken {
  function decimals() external view returns (uint8);

  function pause() external;

  function unpause() external;

  function mint(address to, uint256 amount) external;

  function burn(address from, uint256 amount) external;
}

