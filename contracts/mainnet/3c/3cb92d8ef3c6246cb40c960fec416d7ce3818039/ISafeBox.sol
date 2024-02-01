pragma solidity 0.8.19;

import "./ICToken.sol";

interface ISafeBox {
  function balanceOf(address) external view returns (uint256);

  function cToken() external view returns (ICToken);
}

