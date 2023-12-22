// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

interface IVaultDelegator {
  event Deposit(uint256 amount);
  event Withdraw(uint256 amount);
  event RewardsClaimed(uint256 amount);
  event LinkedVaultUpdated(address indexed vault);
  event ClaimableThresholdUpdated(uint256 threshold);

  function asset() external view returns (address);

  function underlyingContract() external view returns (address);

  function linkedVault() external view returns (address);

  function delegatorName() external pure returns (string memory);

  function delegatorType() external pure returns (string memory);

  function setLinkedVault(address vault) external;

  function setClaimableThreshold(uint256 threshold) external;

  function deposit(uint256 amount) external;

  function withdraw(uint256 amount) external;

  function totalAssets() external view returns (uint256);

  function rewards() external view returns (uint256);

  function claim() external;
}

