// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./JBSplit.sol";

struct RoundInfo {
  uint256 totalContributions;
  uint256 target;
  uint256 hardcap;
  address projectOwner;
  uint256 afterRoundReservedRate;
  JBSplit[] afterRoundSplits;
  bool isRoundClosed;
  uint256 deadline;
  bool isTargetUsd;
  bool isHardcapUsd;
}

