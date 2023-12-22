// SPDX-License-Identifier: NONE
pragma solidity ^0.8.9;

interface IDIAOracleV2 {
  function getValue(string memory key) external view returns(uint128,uint128);
}

