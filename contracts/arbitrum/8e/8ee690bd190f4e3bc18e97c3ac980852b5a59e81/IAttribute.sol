// Dev Note: collapse these down into composable interfaces?
interface IAttribute {
  function attribute() external view returns (uint256);

  function adjustAttribute(uint256 newAttribute) external;

  function getURI() external view returns (uint256);
}

