// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IConversion {

  /**
  * @notice           Obtaining the price ratio between a token and STABLE_COIN
  * @return uint256
  */
  function getPrice(address tokenAddress) external view returns(uint256);

}

