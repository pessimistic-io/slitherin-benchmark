// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

interface ITLCStaking {
  function deposit(address to, uint256 amount) external;

  function withdraw(address to, uint256 amount) external;

  function getUserTokenAmount(
    uint256 epochTimestamp,
    address sender
  ) external view returns (uint256);

  function harvest(
    uint256 startEpochTimestamp,
    uint256 noOfEpochs,
    address[] memory _rewarders
  ) external;

  function harvestToCompounder(
    address user,
    uint256 startEpochTimestamp,
    uint256 noOfEpochs,
    address[] memory _rewarders
  ) external;

  function calculateTotalShare(uint256 epochTimestamp) external view returns (uint256);

  function calculateShare(uint256 epochTimestamp, address user) external view returns (uint256);

  function isRewarder(address rewarder) external view returns (bool);

  function addRewarder(address newRewarder) external;

  function setWhitelistedCaller(address _whitelistedCaller) external;

  function removeRewarder(uint256 _removeRewarderIndex) external;
}

