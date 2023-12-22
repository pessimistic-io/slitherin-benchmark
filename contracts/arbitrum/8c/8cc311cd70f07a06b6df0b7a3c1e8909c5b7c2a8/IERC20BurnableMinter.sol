// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./IERC20Metadata.sol";

interface IERC20BurnableMinter is IERC20Metadata {
  function mint(address to, uint256 amount) external;

  function burn(uint256 amount) external;

  function burnFrom(address account, uint256 amount) external;
}

