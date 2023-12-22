// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IMissionOneStorage {
  function set(
    address _addr,
    uint256 _id,
    uint256 _seconds
  ) external;

  function isEligible(address _addr, uint256 _id) external view returns (bool);
}

