pragma solidity 0.8.19;

interface ICToken {
  function underlying() external view returns (address);

  function exchangeRateStored() external view returns (uint256);
}

