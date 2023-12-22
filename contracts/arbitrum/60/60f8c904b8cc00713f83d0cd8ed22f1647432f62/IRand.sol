// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IRand {
  function retrieve(uint256 _salt) external view returns (uint256);
}

