// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./ITreasury.sol";

contract TreasuryBase {
  IERC20Upgradeable boo;

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  mapping (address => ITreasury.StreamInfo) public streamInfo;

  event StreamAdded(address indexed stream, uint256 amount, uint256 startTimestamp, uint256 endTimestamp);
  event StreamFunded(address indexed stream, uint256 streamFunded, uint256 rewardsPaidInTotal);
  event FundAdded(address indexed stream, uint256 amount);
  event StreamTimeUpdated(address indexed stream, uint256 startTimestamp, uint256 endTimestamp);

  event StreamGrant(address indexed stream, address from, uint256 amount);
  event StreamDefunded(address indexed stream, uint256 amount);
  event StreamRemoved(address indexed stream);

  event RewardsPaid(address indexed stream, uint256 rewardsPaid, uint256 rewardsPaidInTotal);
  event Withdraw(address to, uint256 amount);
}

