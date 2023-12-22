// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IEpochStaking {
  function currentEpoch() external view returns (uint32);

  function epochCheckpoints(uint32) external view returns (uint32, uint32, uint112);

  function stakedCheckpoints(address, uint32) external view returns (uint112);

  function stakedDetails(
    address _user
  ) external view returns (uint112 amount, uint32 lastCheckpoint);

  function advanceEpoch() external;

  function init() external;

  function setWhitelist(address) external;

  function pause() external;

  function unpause() external;
}

