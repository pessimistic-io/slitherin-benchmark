// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./VaultStrategy.sol";

interface ICamelotYieldFarmVault {
  struct VaultConfig {
    // Target leverage of the vault in 1e18
    uint256 targetLeverage;
    // Target Token A debt ratio in 1e18
    uint256 tokenADebtRatio;
    // Target Token B debt ratio in 1e18
    uint256 tokenBDebtRatio;
  }
  function strategy() external view returns (VaultStrategy);
  function tokenA() external view returns (address);
  function tokenB() external view returns (address);
  function treasury() external view returns (address);
  function perfFee() external view returns (uint256);
  function chainlinkOracle() external view returns (address);
  function vaultConfig() external view returns (VaultConfig memory);
}

