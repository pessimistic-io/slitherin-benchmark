// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

interface IHasUpstream {
  function getUpstream() external view returns (address);
}

