// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20_IERC20.sol";

interface IERC20BurnableMintable is IERC20 {
  function burn(uint256 amount) external;

  function burnFrom(address account, uint256 amount) external;

  function mint(address to, uint256 amount) external;
}

