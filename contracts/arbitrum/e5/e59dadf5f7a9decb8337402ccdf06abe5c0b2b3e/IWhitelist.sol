// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IWhitelist {
  function isWhitelisted(address) external view returns (bool);
}

