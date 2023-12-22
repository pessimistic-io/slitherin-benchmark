// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface ILabStorage {
  function set(
    uint256[] calldata _realmIds,
    uint256[] calldata _entityIds,
    uint256[] calldata _amounts
  ) external;
}

