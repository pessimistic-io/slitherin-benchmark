// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IJBPaymentTerminal.sol";
import "./JBFundingCycleData.sol";
import "./JBFundAccessConstraints.sol";
import "./JBGroupedSplits.sol";
import "./JBPayDataSourceFundingCycleMetadata.sol";

/**
  @member data Data that defines the project's first funding cycle. These properties will remain fixed for the duration of the funding cycle.
  @member metadata Metadata specifying the controller specific params that a funding cycle can have. These properties will remain fixed for the duration of the funding cycle.
  @member mustStartAtOrAfter The time before which the configured funding cycle cannot start.
  @member groupedSplits An array of splits to set for any number of groups. 
  @member fundAccessConstraints An array containing amounts that a project can use from its treasury for each payment terminal. Amounts are fixed point numbers using the same number of decimals as the accompanying terminal. The `_distributionLimit` and `_overflowAllowance` parameters must fit in a `uint232`.
  @member terminals Payment terminals to add for the project.
  @member memo A memo to pass along to the emitted event.
*/
struct JBLaunchFundingCyclesData {
  JBFundingCycleData data;
  JBPayDataSourceFundingCycleMetadata metadata;
  uint256 mustStartAtOrAfter;
  JBGroupedSplits[] groupedSplits;
  JBFundAccessConstraints[] fundAccessConstraints;
  IJBPaymentTerminal[] terminals;
  string memo;
}

