// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


interface IGoodEntryCore {
  function treasury() external returns (address);
  function treasuryShareX2() external returns (uint8);
  function setTreasury(address _treasury, uint8 _treasuryShareX2) external;
  function updateReferrals(address _referrals) external;
  function isPaused() external returns(bool);
}
