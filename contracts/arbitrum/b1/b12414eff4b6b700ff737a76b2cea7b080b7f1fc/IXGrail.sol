// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./IERC20.sol";
import "./IXGrailTokenUsage.sol";

interface IXGrail is IERC20 {
  struct XGrailBalance {
    uint256 allocatedAmount; // Amount of xGRAIL allocated to a Usage
    uint256 redeemingAmount; // Total amount of xGRAIL currently being redeemed
  }
  struct RedeemInfo {
    uint256 grailAmount; // GRAIL amount to receive when vesting has ended
    uint256 xGrailAmount; // xGRAIL amount to redeem
    uint256 endTime;
    IXGrailTokenUsage dividendsAddress;
    uint256 dividendsAllocation; // Share of redeeming xGRAIL to allocate to the Dividends Usage contract
  }
  function getXGrailBalance(address user) external view returns (XGrailBalance calldata);
  function getGrailByVestingDuration(uint256 amount, uint256 duration) external view returns (uint256);
  function getUserRedeemsLength(address user) external view returns (uint256);
  function getUserRedeem(address user, uint256 index) external view returns (RedeemInfo calldata);
  function getUsageApproval(address user, address usageAddress) external view returns (uint256);
  function getUsageAllocation(address user, address usageAddress) external view returns (uint256);
  function dividendsAddress() external view returns (address);
  function usagesDeallocationFee(address allocation) external view returns (uint256);
  function grailToken() external view returns (address);
  function minRedeemDuration() external view returns (uint256);

  function approveUsage(address usage, uint256 amount) external;
  function convert(uint256 amount) external;
  function convertTo(uint256 amount, address to) external;
  function redeem(uint256 amount, uint256 duration) external;
  function finalizeRedeem(uint256 redeemIndex) external;
  function updateRedeemDividendsAddress(uint256 redeemIndex) external;
  function cancelRedeem(uint256 redeemIndex) external;
  function allocate(address usage, uint256 amount, bytes calldata usageData) external;
  function deallocate(address usage, uint256 amount, bytes calldata usageData) external;

  function updateTransferWhitelist(address account, bool add) external;
}
