// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IUserProxyManager {
  function createUserProxy() external;

  function getUserProxy() external view returns (address);
}

