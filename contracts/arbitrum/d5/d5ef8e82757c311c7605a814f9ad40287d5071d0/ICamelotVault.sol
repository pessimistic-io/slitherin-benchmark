// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";

interface ICamelotVault {
  struct VaultConfig {
    // Target leverage of the vault in 1e18
    uint256 targetLeverage;
    // Target Token A debt ratio in 1e18
    uint256 tokenADebtRatio;
    // Target Token B debt ratio in 1e18
    uint256 tokenBDebtRatio;
    // Management fee per second in % in 1e18
    uint256 mgmtFeePerSecond;
    // Performance fee in % in 1e18
    uint256 perfFee;
    // Max capacity of vault
    uint256 maxCapacity;
  }
  function tokenA() external view returns (IERC20);
  function tokenB() external view returns (IERC20);
  function treasury() external view returns (address);
  // function perfFee() external view returns (uint256);
  // function chainlinkOracle() external view returns (address);
  // function vaultConfig() external view returns (VaultConfig);
  function getVaultConfig() external view returns (VaultConfig memory);
  function svTokenValue() external view returns (uint256);
  function mintMgmtFee() external;
}

