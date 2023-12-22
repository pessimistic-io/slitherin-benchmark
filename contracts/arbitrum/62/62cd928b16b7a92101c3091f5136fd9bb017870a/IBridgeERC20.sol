// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./IERC20.sol";

interface IBridgeERC20 is IERC20 {
  function mint(address to, uint amount) external;
  function burnFrom(address account, uint256 amount) external;
}

