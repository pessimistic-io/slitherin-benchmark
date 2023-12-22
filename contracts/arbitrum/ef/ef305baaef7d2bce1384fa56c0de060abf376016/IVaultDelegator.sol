// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IVaultDelegator {
  event Fee(uint256 amount);
  event RequestedDeposit(uint256 amount);
  event Deposited(uint256 amount);
  event RequestedWithdraw(uint256 amount);
  event Withdrawn(uint256 amount);
  event LinkedVaultUpdated(address indexed vault);
  event ClaimableThresholdUpdated(uint256 threshold);

  function asset() external view returns (address);

  function underlyingContract() external view returns (address);

  function linkedVault() external view returns (address);

  function setLinkedVault(address vault) external;

  function claimableThreshold() external view returns (uint256);

  function setClaimableThreshold(uint256 threshold) external;

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

  function depositsAvailable(uint256 amount) external view returns (bool);

  function withdrawsAvailable(uint256 amount) external view returns (bool);

  function deposit(uint256 amount) external returns (uint256);

  function withdraw(uint256 amount) external returns (uint256);

  function claim() external;

  function recoverFunds() external;
}

