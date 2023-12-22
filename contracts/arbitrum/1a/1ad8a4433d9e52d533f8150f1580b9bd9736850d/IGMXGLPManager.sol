// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGMXGLPManager {
  function getPrice(bool _maximise) external view returns (uint256);
  function getAumInUsdg(bool _maximise) external view returns (uint256);
  function glp() external view returns (address);
}

