// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IController {
  function addVault(address) external;

  function started() external view returns (bool);

  function tokenClaimEnabled() external view returns (bool);

  function governance() external view returns (address);
}

