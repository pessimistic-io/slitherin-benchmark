// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./IERC721Enumerable.sol";

interface IManager is IERC721Enumerable {
  function vaultMap(uint256 vaultId) external view returns (address);
  function maxVaultsPerUser() external view returns (uint256);
  function keeperRegistry() external view returns (address);
  function perpVaults(address hypervisor) external view returns (address);
  function getTokenPrice(address token) external view returns (uint256);
  function treasury() external view returns (address);
  function getPath(address token0, address token1) external view returns (address, bytes memory);
}

