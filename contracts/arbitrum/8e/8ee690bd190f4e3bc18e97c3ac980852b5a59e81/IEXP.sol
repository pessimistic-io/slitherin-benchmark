interface IEXP {
  function getXP(uint256 characterId) external view returns (uint256);

  function getLVL(uint256 characterId) external view returns (uint256);
}

