// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;
pragma abicoder v2;

interface IGlpManager {
  function getPrice(bool _maximise) external view returns (uint256);
}

