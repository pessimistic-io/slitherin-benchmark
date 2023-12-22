// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./IERC721Enumerable.sol";

interface IManager is IERC721Enumerable {
  function maxVaultsPerUser() external view returns (uint256);
  function keeperRegistry() external view returns (address);
}

