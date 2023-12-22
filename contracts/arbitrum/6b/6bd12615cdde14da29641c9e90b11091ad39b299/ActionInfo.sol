// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
struct ActionInfo {
  uint16 actionId;
  address latest;
  address[] whitelist;
  address[] blacklist;
}

