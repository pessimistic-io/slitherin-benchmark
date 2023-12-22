// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IGlpManager {
  function getPrice(bool _maximise) external view returns (uint256);

  function vault() external view returns (address);
}

