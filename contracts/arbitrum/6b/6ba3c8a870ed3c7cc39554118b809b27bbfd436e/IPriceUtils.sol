// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IPriceUtils {
  function glpPrice() external view returns (uint256);
}
