// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Asset.sol";

// an input asset to a WorkflowStep
struct WorkflowStepInputAsset {
  // the input asset
  Asset asset;
  // the amount of the input asset
  uint256 amount;
  // if true 'amount' is treated as a percent, with 4 decimals of precision (1000000 represents 100%)
  bool amountIsPercent;
}

// Parameters for a workflow step
struct WorkflowStep {
  // The logical identifer of the step (e.g., 10 represents WrapEtherStep).
  uint16 actionId;
  // The contract address of a specific version of the action.
  // Individual step contracts may be upgraded over time, and this allows
  // workflows 'freeze' the version of contract for this step
  // A value of address(0) means use the latest and greatest version  of
  // this step based only on actionId.
  address actionAddress;
  // The input assets to this step.
  WorkflowStepInputAsset[] inputAssets;
  // The output assets for this step.
  Asset[] outputAssets;
  // Additional step-specific parameters for this step, typically serialized in standard abi encoding.
  bytes data;
  // The index of the next step in the directed graph of steps. (see the Workflow.steps array)
  int16 nextStepIndex;
}

// The main workflow data structure.
struct Workflow {
  // The nodes in the directed graph of steps.
  // The start step is defined to be at index 0.
  // The 'edges' in the graph are defined within each WorkflowStep,
  // but can be overriden in the return value of a step.
  WorkflowStep[] steps;
}

