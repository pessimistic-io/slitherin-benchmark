// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IVaultDelegator {
  event Fee(uint256 amount);
  event RequestedDeposit(uint256 amount);
  event Deposited(uint256 amount);
  event RequestedWithdraw(uint256 amount);
  event Withdrawn(uint256 amount);
  event RequestedByAddress(address indexed user);
  event LinkedVaultUpdated(address indexed vault);
  event ClaimableThresholdUpdated(uint256 threshold);
  event SlippageConfigurationUpdated(uint256 amount);

  function asset() external view returns (address);

  function underlyingContract() external view returns (address);

  function linkedVault() external view returns (address);

  function setLinkedVault(address vault) external;

  function claimableThreshold() external view returns (uint256);

  function setClaimableThreshold(uint256 threshold) external;

  function slippageConfiguration() external view returns (uint256);

  function setSlippageConfiguration(uint256 amount) external;

  function delegatorName() external pure returns (string memory);

  function delegatorType() external pure returns (string memory);

  function estimatedTotalAssets() external view returns (uint256);

  function rewards() external view returns (uint256);

  function integrationFeeForDeposits(
    uint256 amount
  ) external view returns (uint256);

  function integrationFeeForWithdraws(
    uint256 amount
  ) external view returns (uint256);

  function deposit(uint256 amount, address user) external returns (uint256);

  function withdraw(uint256 amount, address user) external returns (uint256);

  function claim() external;

  function recoverFunds() external;
}

