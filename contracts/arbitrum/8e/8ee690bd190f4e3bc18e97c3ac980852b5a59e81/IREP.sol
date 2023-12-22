interface IREP {
  function getREP(uint256 characterId) external view;

  function getRNK(uint256 characterId) external view returns (uint256);
}

