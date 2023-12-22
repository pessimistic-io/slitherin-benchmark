// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICamelotXGrail {
  function allocate(
    address usageAddress,
    uint256 amount,
    bytes calldata usageData
  ) external;

  function deallocate(
    address usageAddress,
    uint256 amount,
    bytes calldata usageData
  ) external;


  function redeem(
    uint256 amount,
    uint256 duration
  ) external;

  function finalizeRedeem(
    uint256 index
  ) external;

  function approveUsage(IXGrailTokenUsage usage, uint256 amount) external;

  function minRedeemDuration() external view returns (uint256);

  function getUserRedeemsLength(address userAddress) external view returns (uint256);

  function getUserRedeem(address userAddress, uint256 index) external view returns (uint256, uint256, uint256, address, uint256);

  function getUsageAllocation(address userAddress, address usageAddress) external view returns (uint256);
}

interface IXGrailTokenUsage {
    function allocate(address userAddress, uint256 amount, bytes calldata data) external;
    function deallocate(address userAddress, uint256 amount, bytes calldata data) external;
}

