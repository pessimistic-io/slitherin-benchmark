// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGMXPerpetualDEXLongVault {
  struct VaultConfig {
    // Target leverage of the vault in 1e18
    uint256 targetLeverage;
  }

  function token() external view returns (address);
  function treasury() external view returns (address);
  function perfFee() external view returns (uint256);
  function chainlinkOracle() external view returns (address);
  function vaultConfig() external view returns (VaultConfig memory);
}

