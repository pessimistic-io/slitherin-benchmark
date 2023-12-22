// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IConversion {

  /**
  * @notice           获取token跟STABLE_COIN的价格比
  * @return uint256
  */
  function getPrice(address tokenAddress) external view returns(uint256);

}

