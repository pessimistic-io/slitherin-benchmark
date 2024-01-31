pragma solidity ^0.4.23;

interface IKYTE {
  function name() external view returns (string);
  function symbol() external view returns (string);
  function decimals() external view returns (uint256);
}
