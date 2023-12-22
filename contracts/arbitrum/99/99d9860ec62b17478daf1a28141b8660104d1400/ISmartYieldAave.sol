// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

// smart yield with aave v2 as originator

interface ISmartYieldAave {
  function activeTerm() external returns (address);
  function bondData(address _term) external returns (
    uint256 start,
    uint256 end,
    uint256 feeRate,
    address nextTerm,
    address bond,
    uint256 realizedYield,
    bool liquidated
  );
  function liquidateTerm(address _term) external;
}

