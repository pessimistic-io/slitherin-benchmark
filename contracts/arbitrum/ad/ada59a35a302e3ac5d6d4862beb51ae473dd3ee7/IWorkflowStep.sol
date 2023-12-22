// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./Asset.sol";
import "./AssetAmount.sol";
import "./WorkflowStepResult.sol";

interface IWorkflowStep {
  function execute(
    // input assets paired with amounts of each
    AssetAmount[] calldata inputAssetAmounts,
    // expected output assets (amounts not known yet)
    Asset[] calldata outputAssets,
    // additional arguments specific to this step
    bytes calldata data
  ) external payable returns (WorkflowStepResult memory);
}

