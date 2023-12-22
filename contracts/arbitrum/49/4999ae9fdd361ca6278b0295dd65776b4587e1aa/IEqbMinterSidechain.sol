// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IEqbMinterSidechain {
  function DENOMINATOR() external view returns (uint256);

  function getFactor() external view returns (uint256);
}

