// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20MetadataUpgradeable.sol";

interface IERC20MintableBurnableUpgradeable is IERC20MetadataUpgradeable {
  function mint(address to, uint256 amount) external;
  function burn(address to, uint256 amount) external;
  function burn(uint256 amount) external;
}
