// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IERC20Metadata.sol";

interface IDIPX is IERC20Metadata{
  function mint(address to, uint256 value) external;
}

