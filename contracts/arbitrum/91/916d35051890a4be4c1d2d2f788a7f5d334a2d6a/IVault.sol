// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./IERC4626.sol";

interface IVault is IERC4626 {
  event Sponsored(uint256 amount, address indexed sponsor, string sponsorName);

  function getDelegatorName() external view returns (string memory);

  function getDelegatorType() external view returns (string memory);

  function checkApproval(address user) external view returns (bool);

  function checkApproval(
    address user,
    uint256 allowance
  ) external view returns (bool);

  function depositFee() external view returns (uint256);

  function depositIntegrationFee(
    uint256 amount
  ) external view returns (uint256);

  function totalFeeForDeposits(uint256 amount) external view returns (uint256);

  function estimateDepositAfterFees(
    uint256 amount
  ) external view returns (uint256);

  function withdrawFee() external view returns (uint256);

  function withdrawIntegrationFee(
    uint256 amount
  ) external view returns (uint256);

  function totalFeeForWithdraws(uint256 amount) external view returns (uint256);

  function estimateWithdrawAfterFees(
    uint256 amount
  ) external view returns (uint256);

  function minDeposit() external view returns (uint256);

  function maxDeposit() external view returns (uint256);

  function minMint() external view returns (uint256);

  function maxMint() external view returns (uint256);

  function initialDeposit(
    uint256 assets,
    address receiver
  ) external returns (uint256);

  function sponsorTheVault(
    uint256 assets,
    string memory sponsorName
  ) external returns (uint256);

  function emergencyExit(
    uint256 shares,
    address receiver,
    address owner
  ) external returns (uint256);
}

