//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IGlobalIncentivesHelper {
  function notifyPools(address[] calldata tokens, uint256[] calldata totals, uint256 timestamp) external;
}
