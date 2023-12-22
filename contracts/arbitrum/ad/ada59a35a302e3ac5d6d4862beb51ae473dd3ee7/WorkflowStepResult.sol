// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./AssetAmount.sol";

// The return value from the execution of a step.
struct WorkflowStepResult {
  // The amounts of each output asset that resulted from the step execution.
  AssetAmount[] outputAssetAmounts;
  // The index of the next step in a workflow.
  // This value allows the step to override the default nextStepIndex
  // statically defined
  // -1 means terminate the workflow
  // -2 means do not override the statically defined nextStepIndex in WorkflowStep
  int16 nextStepIndex;
}

