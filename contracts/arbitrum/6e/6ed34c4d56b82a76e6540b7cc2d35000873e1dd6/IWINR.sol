// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "./IERC20.sol";

interface IWINR is IERC20 {
  function mint(address account, uint256 amount) external returns (uint256, uint256);

  function burn(uint256 amount) external;

  function MAX_SUPPLY() external view returns (uint256);
}

