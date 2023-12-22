// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IPlsDpxRewardsDistro {
  function updateHarvestDetails(
    uint256 _timestamp,
    uint256 _dpx,
    uint256 _rdpx
  ) external;
}

