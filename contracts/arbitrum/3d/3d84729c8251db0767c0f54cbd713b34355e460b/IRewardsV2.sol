// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "./ERC20.sol";

interface IRewardsV2 {
  function distributedTokensLength() external view returns (uint256);
  function distributedToken(uint256 index) external view returns (address);
  function isDistributedToken(address token) external view returns (bool);
  function addRewardsToPending(ERC20 token, address distributor, uint256 amount) external;
}
