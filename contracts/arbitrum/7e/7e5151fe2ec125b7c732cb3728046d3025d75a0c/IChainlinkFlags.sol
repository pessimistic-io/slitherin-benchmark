// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0 <0.8.0;

interface IChainlinkFlags {
  function getFlag(address) external view returns (bool);
}

