// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface ICvaFactory {
  function forwarderAddress() external view returns (address);

  function bridgeAddress() external view returns (address);

  function handlerAddress() external view returns (address);

  function relayerAddress() external view returns (address);

  function wethAddress() external view returns (address);

  function owner() external view returns (address);

  function isForwarderDeployed(address) external view returns (bool);

  function getForwarder(bytes calldata, bytes calldata) external view returns (address);

  function hasRole(bytes32 role, address account) external view returns (bool);

  function isValid() external view returns (bool);

  function createForwarder(bytes calldata, bytes calldata) external;

  function emitNativeReceived(address, address, uint256) external;
}

