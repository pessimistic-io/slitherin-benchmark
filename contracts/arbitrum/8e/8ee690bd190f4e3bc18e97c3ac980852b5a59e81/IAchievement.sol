pragma solidity ^0.8.0;

interface IAchievement {
  function getAchievement() external view returns (string memory);

  function hasAchievement(uint256 characterId) external view returns (bool);

  function unlockAchievement(uint256 characterId) external view;
}

