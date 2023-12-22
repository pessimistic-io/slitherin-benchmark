// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IBeacon {
  function tokensByAccount(address user)
    external
    view
    returns (uint256[] memory tokenIds);
}

