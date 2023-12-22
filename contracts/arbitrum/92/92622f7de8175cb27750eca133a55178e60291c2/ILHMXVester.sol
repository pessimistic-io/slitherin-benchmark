// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILHMXVester {
  function claimFor(uint256 amount) external;

  function endCliffTimestamp() external returns (uint256);

  function setEndCliffTimestamp(uint256 _endCliffTimestamp) external;

  function setHmxStaking(address newHmxStaking) external;

  function getUserClaimedAmount(address account)
    external
    view
    returns (uint256);

  function getTotalLHMXAmount(address account)
    external
    view
    returns (uint256 amount);

  function getUnlockAmount(address account) external view returns (uint256);
}

