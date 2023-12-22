
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IGlpManager {
   function getAumInUsdg(bool) external view returns (uint256);
   function cooldownDuration() external view returns (uint256);   
   function lastAddedAt(address _account) external view returns (uint256);   
}


